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

  # Move this book's *series* membership to another series (or nil to make it
  # standalone). Collections are untouched. Both the vacated and the receiving
  # series stay numbered 1..n; the book lands at the end of its new series.
  def shelve_in_series(target_series_record_id)
    target = target_series_record_id.presence&.to_i
    old_ids = Series.current.where(record_id: installments.select(:container_record_id)).pluck(:record_id)
    return if old_ids == [ target ].compact # already exactly there — nothing to do

    Installment.transaction do
      installments.where(container_record_id: old_ids).delete_all
      if target
        position = (Installment.where(container_record_id: target).maximum(:position) || 0) + 1
        installments.create!(container_record_id: target, position: position)
      end
      (old_ids + [ target ]).compact.uniq.each { |id| Installment.renumber(id) }
    end
  end
end
