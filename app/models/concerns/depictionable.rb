# Mix into a recordable to give it a versioned cover image. The image lives on
# a separate Depiction (like Body holds rich text), referenced by a scalar
# depiction_id so build_successor's dup carries an unchanged cover forward and
# only a real cover change mints a new Depiction — "did the cover change?" is a
# depiction_id compare, the same shape as body_id. See Book.
module Depictionable
  extend ActiveSupport::Concern

  included do
    belongs_to :depiction, optional: true
    after_destroy :discard_orphaned_depiction
  end

  # True when this version actually carries a cover image.
  def cover?
    depiction&.image&.attached? || false
  end

  # The 600×900 cover variant (book detail / cards) and the 256×256 thumb
  # (compact lists). Nil when there's no cover — callers fall back.
  def cover
    depiction.image.variant(:cover) if cover?
  end

  def cover_thumb
    depiction.image.variant(:thumb) if cover?
  end

  private
    # Depictions are shared between versions; only destroy one when its last
    # referencing version goes (mirrors Publishable#discard_orphaned_body).
    def discard_orphaned_depiction
      return if depiction_id.nil?
      depiction.destroy unless self.class.exists?(depiction_id: depiction_id)
    end
end
