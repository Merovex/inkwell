# The operational tenant: the press or pen name everything else belongs to.
# Plain table, not a recordable — accounts own the spine; they don't live on
# it. The slug is the account's only public identifier (support tickets, R2
# prefixes, Stripe metadata); the primary key never leaves the database.
# Ownership transfers are a deliberate console operation, not a UI flow.
class Account < ApplicationRecord
  include Sluggable
  self.slug_param_only = true

  belongs_to :owner, class_name: "User"

  validates :name, presence: true
end
