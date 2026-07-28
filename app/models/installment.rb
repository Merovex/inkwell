# A book's placement in a series: a join between two Records (the stable
# identities, never version rows), so a book can belong to many series and a
# series orders its books by `position`. Created/destroyed as books are added
# to or removed from a series; reordered from the series admin page.
class Installment < ApplicationRecord
  belongs_to :series_record, class_name: "Record"
  belongs_to :book_record, class_name: "Record"

  validates :book_record_id, uniqueness: { scope: :series_record_id }
  # Tenancy rides the two record rows; a cross-account pairing must be
  # unrepresentable (SQLite can't express this constraint — AR only).
  validate :records_share_account

  private
    def records_share_account
      return if series_record&.account_id == book_record&.account_id
      errors.add(:base, "Series and book must belong to the same account")
    end
end
