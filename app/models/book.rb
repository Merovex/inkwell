# A book — a recordable on the spine, Publishable like Post/Message, with two
# additions: a real-world publication_date (when the book was released to the
# world, distinct from published_at — when this record went live) and a
# versioned cover (Depictionable). Series membership + order live on the
# Installment join, keyed by Record id so they survive versioning.
class Book < ApplicationRecord
  include Publishable
  include Depictionable

  has_many :installments, primary_key: :record_id, foreign_key: :book_record_id,
    dependent: :destroy

  # The series this book appears in, as current Series versions.
  def series
    Series.current.where(record_id: installments.select(:series_record_id))
  end
end
