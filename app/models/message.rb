# A message on the board (/forum) — the fourth recordable on the spine.
# Publishable exactly like Post (drafts mutate in place, published content
# versions on every save, scheduling via an event version + job) with one
# addition: an optional Category, worn in the byline. Category is a column
# like any other, so it carries across versions and its changes are history.
class Message < ApplicationRecord
  include Publishable

  belongs_to :category, optional: true

  # optional: true skips existence checks, so a tampered category_id would
  # otherwise sail through valid? and die on the FK mid-transaction. And a
  # category must belong to the same press as the message (ADR 0017).
  validates :category, presence: { message: "must exist" }, if: -> { category_id.present? }
  validate :category_shares_account

  private
    def category_shares_account
      return unless category
      errors.add(:category, "must exist") if category.account_id != (record&.account_id || Current.account&.id)
    end
end
