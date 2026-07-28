# The operational tenant: the press or pen name everything else belongs to.
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
  has_many :records
  has_many :missives

  validates :name, presence: true

  # Account-scoped counterparts of each content type's `.current` scope —
  # the sanctioned starting point for every content query (ADR 0017):
  # current versions of this account's live records, written out plainly,
  # one per type the controllers actually list.
  def posts    = Post.where(id: records.active.posts.select(:recordable_id))
  def messages = Message.where(id: records.active.messages.select(:recordable_id))
  def books    = Book.where(id: records.active.books.select(:recordable_id))
  def series   = Series.where(id: records.active.series.select(:recordable_id))
  def drips    = Drip.where(id: records.active.drips.select(:recordable_id))
  def authors  = Author.where(id: records.active.authors.select(:recordable_id))
  def chat_lines = ChatLine.where(id: records.active.chat_lines.select(:recordable_id))

  # The account's public-site identity, read on every public request — cached,
  # self-busting on edit (Site's after_commit), created on first read so a new
  # account renders sensibly before anyone touches /admin/settings.
  def site
    Rails.cache.fetch([ "site", id ]) do
      Site.where(id: records.active.where(recordable_type: "Site").select(:recordable_id)).first || create_site
    end
  end

  # Resolving an account from a URL identifies it; membership authorizes it.
  # The owner is always a member, join row or not.
  def member?(user)
    user.present? && (owner_id == user.id || account_users.exists?(user: user))
  end

  private
    def create_site
      site = Site.new(site_name: name, creator: owner)
      Current.with_account(self) { Record.originate(site) }
      site
    end
end
