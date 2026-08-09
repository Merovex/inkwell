# A book's placement in an ordered container — a Series or a Collection — as a
# join between two Records (the stable identities, never version rows), so a
# book can belong to many containers and each orders its books by `position`.
# Created/destroyed as books are added to or removed from a container;
# reordered from the container's admin page.
class Installment < ApplicationRecord
  belongs_to :container_record, class_name: "Record"
  belongs_to :book_record, class_name: "Record"

  validates :book_record_id, uniqueness: { scope: :container_record_id }
  # Tenancy rides the two record rows; a cross-account pairing must be
  # unrepresentable (SQLite can't express this constraint — AR only).
  validate :records_share_account

  # Rewrite a container's positions to a contiguous 1..n in current order, after
  # a book has been added to or removed from it (see Book#shelve_in_series).
  def self.renumber(container_record_id)
    where(container_record_id: container_record_id).order(:position).each_with_index do |installment, i|
      installment.update_columns(position: i + 1)
    end
  end

  private
    def records_share_account
      return if container_record&.bucket_id == book_record&.bucket_id
      errors.add(:base, "Container and book must belong to the same account")
    end
end
