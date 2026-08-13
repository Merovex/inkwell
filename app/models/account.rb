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
  # Weekly readings of the sendable subscriber count — the digest's trend + baseline.
  has_many :subscriber_snapshots, dependent: :delete_all
  # Connected custom hostnames (apex + www rows) on the Cloudflare-for-SaaS
  # path. Destroying an account drops its rows; the KV keys and Cloudflare
  # custom hostnames are torn down by the disconnect flow, not this cascade.
  has_many :custom_domains, dependent: :destroy
  # Connected BYOD email identities (docs/email-tenant-byod-plan.md) — same
  # deal: rows cascade here, the SES identity is torn down by the disconnect
  # flow (EmailConnection), not this cascade.
  has_many :sending_domains, dependent: :destroy

  # The public site's design as versioned records (SiteDesignVersion): one
  # `drafted` working copy the SiteDesigner edits and the preview host serves,
  # one `published` copy production builds from, and archived history behind
  # them. Seeded on create so both always exist.
  has_many :site_design_versions, dependent: :destroy
  has_one :draft_design, -> { drafted }, class_name: "SiteDesignVersion"
  has_one :published_design, -> { published }, class_name: "SiteDesignVersion"
  after_create :seed_design_versions

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  # The author-chosen Kindred Quill name — Buttondown's shape, on two
  # surfaces: the shared-lane From (<handle>@kindredquill.email) and the
  # platform URL (sites.kindredquill.com/<handle>). NULL until claimed; both
  # surfaces fall back (noreply@, the slug path) meanwhile. Reserved words
  # keep operational/deceptive local parts off the shared domain AND
  # plausible root paths off the platform host.
  RESERVED_HANDLES = %w[
    abuse admin administrator api app assets billing blog bounce bounces
    cdn contact demo dev docs feed ftp help hostmaster info inkwell
    kindredquill legal mail mailer-daemon marketing moderator news
    newsletter noreply no-reply official postmaster posts preview privacy root
    rss sales search security site sites smtp staff staging static status
    subscribe support team test unsubscribe verify webmaster www
  ].freeze

  HANDLE_FORMAT = /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/

  normalizes :handle, with: ->(handle) { handle.strip.downcase.presence }
  validates :handle, allow_nil: true,
    length: { in: 3..30 },
    format: { with: HANDLE_FORMAT,
              message: "can use lowercase letters, numbers, and hyphens (not at the ends)" },
    exclusion: { in: RESERVED_HANDLES, message: "is reserved" },
    uniqueness: true

  # A free variant of a wanted-but-taken handle: base-{4d}, a random 4-digit
  # tail (the availability typeahead's counter-offer). Nil when five draws
  # all collide — vanishingly unlikely, and the typeahead just stays silent.
  def self.suggest_handle(base)
    base = base.first(25) # leave room for "-1234" inside the 30-char cap
    5.times do
      candidate = "#{base}-#{format("%04d", SecureRandom.random_number(10_000))}"
      return candidate unless RESERVED_HANDLES.include?(candidate) || exists?(handle: candidate)
    end
    nil
  end

  # The moderation override for records in this bucket: an account admin. The
  # bucket-owner interface Record#moderatable_by? leans on (Circle answers this
  # with its owner).
  def moderated_by?(user) = user&.administers?(self)

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

  # The public site's address: the custom domain, else the sites-host handle
  # path (slug until a handle is claimed) — where the static build is served.
  # A design change no longer republishes on its own — the author edits the
  # draft and deploys explicitly (draft_design → preview, publish_design! →
  # production). Infrastructure moves still force a production rebuild: the
  # domain changing hands (go-live stamp or disconnect clear) re-renders every
  # asset/link against the new baseURL.
  after_update_commit -> { SiteBuildJob.schedule(self) }, if: :saved_change_to_domain?
  # A handle change moves the platform URL: rebuild (baseURL embeds the
  # handle path) and re-point the edge alias (KV handle:<name> → slug).
  after_update_commit -> { SiteBuildJob.schedule(self) }, if: :saved_change_to_handle?
  after_update_commit :sync_handle_route, if: :saved_change_to_handle?
  # The SES-provisioning stamp is the export contract's newsletter-signup
  # gate: flipping it turns the baked band's mailto CTA into the real form,
  # so the site re-publishes on its own.
  after_update_commit -> { SiteBuildJob.schedule(self) }, if: :saved_change_to_ses_tenant_provisioned_at?

  def public_address
    domain || "#{AccountHost.sites_host}/#{handle.presence || slug}"
  end

  # SiteBuildJob's status stamps. update_columns on purpose — a build's own
  # bookkeeping must never trip the rebuild callbacks above — so the designer
  # topbar's live badge broadcast rides here instead of a model callback.
  def stamp_build_status!(status, built_at: nil)
    update_columns({ site_build_status: status, site_built_at: built_at }.compact)
    broadcast_replace_later_to [ self, :build_status ], target: "site-build-status",
      partial: "admin/designers/build_status", locals: { account: self }
  end

  # The staging address a draft design deploys to for a second opinion — the
  # preview host under the handle path (falling back to the slug), served
  # noindex by the edge Worker's preview lane.
  def preview_url
    "https://#{Rails.configuration.x.cloudflare.preview_host}/#{handle.presence || slug}/"
  end

  # Promote the working design to production: the current live design steps
  # down to history, the draft becomes live, and a fresh draft is forked from
  # it so the author keeps editing where they left off. The production rebuild
  # is scheduled after the transaction commits so it never races the write.
  def publish_design!(by: Current.user)
    transaction do
      published_design&.update!(status: :archived)
      draft = draft_design
      draft.update!(status: :published, published_at: Time.current)
      site_design_versions.create!(status: :drafted, data: draft.data, created_by: by)
    end
    SiteBuildJob.schedule(self)
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
  # moment persists. Provisioned automatically when the author connects a
  # sending domain (EmailConnection#connect); console-run for accounts comped
  # without one (Tenant Zero was).
  def ses_tenant_name = "site-#{slug}"
  def ses_tenant_provisioned? = ses_tenant_provisioned_at.present?

  # The account's Turnstile widget secret (TurnstileConnection stamps it,
  # TurnstileVerifier reads it). Encrypted at rest — backups and raw DB access
  # see ciphertext; the model reader decrypts transparently, so console
  # debugging is unchanged. Keys: credentials active_record_encryption.
  encrypts :turnstile_secret_key

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

    def sync_handle_route
      HandleRouteJob.perform_later(self, saved_change_to_handle.first)
    end

    # A new account starts with an empty live design and a matching draft, so
    # production has something to build and the designer always has a draft to
    # edit. Runs inside create_with_owner's transaction.
    def seed_design_versions
      site_design_versions.create!(status: :published, published_at: Time.current)
      site_design_versions.create!(status: :drafted)
    end
end
