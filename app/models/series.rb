# A book series — a recordable on the spine, Publishable exactly like Post
# (drafts mutate in place, published content versions on every save,
# scheduling via an event version + job). Its books are the Installment join,
# keyed by Record id so memberships survive versioning.
class Series < ApplicationRecord
  include Publishable

  has_many :installments, primary_key: :record_id, foreign_key: :series_record_id,
    dependent: :destroy

  # The series' books as current versions, in series order (Installment
  # position). A relation, so callers can chain (e.g. .published on the catalog).
  def books
    Book.current.joins(:installments)
      .where(installments: { series_record_id: record_id })
      .order("installments.position").includes(:record, :depiction)
  end
end
