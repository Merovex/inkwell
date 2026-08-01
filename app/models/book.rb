# A book — a recordable on the spine, Publishable like Post/Message, with two
# additions: a real-world publication_date (when the book was released to the
# world, distinct from published_at — when this record went live) and a
# versioned cover (Depictionable). Container membership + order live on the
# Installment join, keyed by Record id so they survive versioning.
class Book < ApplicationRecord
  include Publishable
  include Depictionable
  include Authored

  has_many :installments, primary_key: :record_id, foreign_key: :book_record_id,
    dependent: :destroy

  # The series this book appears in, as current Series versions. Collection
  # containers share the join but never match Series.current, so they're
  # naturally excluded here (and surfaced by #collections instead).
  def series
    Series.current.where(record_id: installments.select(:container_record_id))
  end

  # The collections this book appears in, as current Collection versions.
  def collections
    Collection.current.where(record_id: installments.select(:container_record_id))
  end
end
