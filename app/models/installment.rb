# A book's placement in a series: a join between two Records (the stable
# identities, never version rows), so a book can belong to many series and a
# series orders its books by `position`. Created/destroyed as books are added
# to or removed from a series; reordered from the series admin page.
class Installment < ApplicationRecord
  belongs_to :series_record, class_name: "Record"
  belongs_to :book_record, class_name: "Record"

  validates :book_record_id, uniqueness: { scope: :series_record_id }
end
