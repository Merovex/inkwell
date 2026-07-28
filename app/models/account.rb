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

  validates :name, presence: true

  # Resolving an account from a URL identifies it; membership authorizes it.
  # The owner is always a member, join row or not.
  def member?(user)
    user.present? && (owner_id == user.id || account_users.exists?(user: user))
  end
end
