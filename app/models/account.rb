# The operational tenant: the site or pen name everything else belongs to.
# Plain table, not a recordable — accounts own the spine; they don't live on
# it. The slug is the account's only public identifier (support tickets, R2
# prefixes, Stripe metadata); the primary key never leaves the database.
# Ownership transfers are a deliberate console operation, not a UI flow.
class Account < ApplicationRecord
  include Sluggable
  self.slug_param_only = true

  belongs_to :owner, class_name: "User"

  has_many :account_users, dependent: :destroy
  has_many :users, through: :account_users
  # The site owns its content as a bucket on the spine (the other bucket kind
  # is a Circle). Every Current.account.records… query keeps working through
  # this association — it just carries a bucket_type of "Account" now.
  has_many :records, as: :bucket
  has_many :missives
  has_many :subscribers
  has_many :categories
  has_many :broadcasts, through: :records
  has_many :ahoy_visits, class_name: "Ahoy::Visit"
  # Connected custom hostnames (apex + www rows) on the Cloudflare-for-SaaS
  # path. Destroying an account drops its rows; the KV keys and Cloudflare
  # custom hostnames are torn down by the disconnect flow, not this cascade.
  has_many :custom_domains, dependent: :destroy
  # Connected BYOD email identities (docs/email-tenant-byod-plan.md) — same
  # deal: rows cascade here, the SES identity is torn down by the disconnect
  # flow (EmailConnection), not this cascade.
  has_many :sending_domains, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  # The author-chosen local part of the shared-lane From address —
  # <handle>@kindredquill.email, Buttondown's shape. NULL until claimed; the
  # shared lane falls back to noreply@ meanwhile. Reserved words keep the
  # operational and deceptive local parts off the shared domain.
  RESERVED_HANDLES = %w[
    abuse admin administrator api billing bounce bounces contact help
    hostmaster info inkwell kindredquill legal mail mailer-daemon marketing
    moderator news newsletter noreply no-reply official postmaster privacy
    root sales security staff subscribe support team unsubscribe verify
    webmaster www
  ].freeze

  normalizes :handle, with: ->(handle) { handle.strip.downcase.presence }
  validates :handle, allow_nil: true,
    length: { in: 3..30 },
    format: { with: /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/,
              message: "can use lowercase letters, numbers, and hyphens (not at the ends)" },
    exclusion: { in: RESERVED_HANDLES, message: "is reserved" },
    uniqueness: true

  # The moderation override for records in this bucket: an account admin. The
  # bucket-owner interface Record#moderatable_by? leans on (Circle answers this
  # with its owner).
  def moderated_by?(user) = user&.administers?(self)

  # The public site's saved design (the SiteDesigner's working payload —
  # axes + content blocks + escape valves). Validated at the controller by
  # SiteDesign before it lands here; the exporter reads it for real builds.
  serialize :design, coder: JSON

  # Account-scoped counterparts of each content type's `.current` scope —
  # the sanctioned starting point for every content query (ADR 0017):
  # current versions of this account's live records, written out plainly,
  # one per type the controllers actually list.
  def posts    = Post.where(id: records.active.posts.select(:recordable_id))
  def messages = Message.where(id: records.active.messages.select(:recordable_id))
  def books    = Book.where(id: records.active.books.select(:recordable_id))
  def series   = Series.where(id: records.active.series.select(:recordable_id))
  def collections = Collection.where(id: records.active.collections.select(:recordable_id))
  def drips    = Drip.where(id: records.active.drips.select(:recordable_id))
  def authors  = Author.where(id: records.active.authors.select(:recordable_id))
  def chat_lines = ChatLine.where(id: records.active.chat_lines.select(:recordable_id))

  # The account's public-site identity, created on first read so a new account
  # renders sensibly before anyone touches /admin/settings. One indexed query;
  # memoized because the layout and etags both ask within a request.
  def site
    @site ||= Site.where(id: records.active.where(recordable_type: "Site").select(:recordable_id)).first || create_site
  end

  # Birth of an account: the site plus its owner's membership, atomically.
  # The owner's superuser authority is the owner_id itself (User#administers?);
  # ownership transfers are a console operation, never UI. Returns the account,
  # unsaved with errors when invalid (name taken, blank).
  def self.create_with_owner(name:, owner:)
    account = new(name: name, owner: owner)
    transaction do
      account.account_users.create!(user: owner) if account.save
    end
    account
  end

  # Where this site's admin lives on the app host (script_name-mounted).
  def admin_path
    "/#{slug}/admin"
  end

  # The public site's address: the custom domain, else the apex slug path.
  # A saved SiteDesigner design re-publishes the static site; so does the
  # domain changing hands (go-live stamp or disconnect clear) — the build's
  # baseURL is the domain, so every asset/link must re-render against it.
  after_update_commit -> { SiteBuildJob.schedule(self) }, if: :saved_change_to_design?
  after_update_commit -> { SiteBuildJob.schedule(self) }, if: :saved_change_to_domain?

  def public_address
    domain || [ AccountHost.apex_host, slug ].compact.join("/")
  end

  # The shared sending domain every un-BYOD site mails from (bought 2026-08-06)
  # — registrable-domain-separate from kindredquill.com so customer bulk never
  # shares reputation with auth mail (docs/email-tenant-byod-plan.md). The
  # credential override is a rename without a deploy, mirroring ses.*_from.
  def self.shared_sending_domain
    Rails.application.credentials.dig(:ses, :shared_sending_domain).presence || "kindredquill.email"
  end

  # This site's SES tenant, the container its sending reputation accrues in.
  # The name is derived — the slug is immutable — so only the provisioning
  # moment persists. Created when the author buys broadcast email
  # (EmailConnection.provision_tenant; console-run for Tenant Zero).
  def ses_tenant_name = "site-#{slug}"
  def ses_tenant_provisioned? = ses_tenant_provisioned_at.present?

  # The address this site's broadcast mail sends from: its live BYOD domain
  # when one exists, else the shared lane. The Email tab shows the bare
  # address; mailers use broadcast_from, which wraps it in the public site's
  # name — never a person's (the old marketing_from hardcoded one).
  def broadcast_address
    if (byod = sending_domains.live.first)
      "noreply@#{byod.domain}"
    else
      "#{handle.presence || "noreply"}@#{self.class.shared_sending_domain}"
    end
  end

  def broadcast_from
    ActionMailer::Base.email_address_with_name(broadcast_address, site.site_name)
  end

  private
    def create_site
      site = Site.new(site_name: name, creator: owner)
      Current.with_account(self) { Record.originate(site) }
      site
    end
end
