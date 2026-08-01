# An ordered container of books via the Installment join, keyed by Record id so
# memberships survive versioning. Mixed into every recordable that shelves books
# in order — Series and Collection behave identically here.
module Installable
  extend ActiveSupport::Concern

  included do
    has_many :installments, primary_key: :record_id, foreign_key: :container_record_id,
      dependent: :destroy
  end

  # The container's books as current versions, in container order (Installment
  # position). A relation, so callers can chain (e.g. .published on the catalog).
  def books
    Book.current.joins(:installments)
      .where(installments: { container_record_id: record_id })
      .order("installments.position").includes(:record, :depiction)
  end
end
