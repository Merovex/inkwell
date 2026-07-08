# A book series — a recordable on the spine, Publishable exactly like Post
# (drafts mutate in place, published content versions on every save,
# scheduling via an event version + job). Its books are the Installment join,
# keyed by Record id so memberships survive versioning.
class Series < ApplicationRecord
  include Publishable

  has_many :installments, primary_key: :record_id, foreign_key: :series_record_id,
    dependent: :destroy

  # The series' books as current versions, in series order (Installment
  # position). Missing/unpublished books simply drop out.
  def books
    ids = installments.order(:position).pluck(:book_record_id)
    by_record = Book.current.where(record_id: ids)
      .includes(:record, :depiction).index_by(&:record_id)
    ids.filter_map { |record_id| by_record[record_id] }
  end
end
