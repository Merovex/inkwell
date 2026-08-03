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

  validates :name, presence: true, uniqueness: { case_sensitive: false }

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
  def public_address
    domain || [ AccountHost.apex_host, slug ].compact.join("/")
  end

  private
    def create_site
      site = Site.new(site_name: name, creator: owner)
      Current.with_account(self) { Record.originate(site) }
      site
    end
end
