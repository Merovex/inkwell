# A public pen name / persona on the Record spine — the byline the site shows
# (Ben Wilson, Troy Buzby…). A Recordable, but always-live and edited in place
# (mutable?), so no draft/publish regime; only trash/restore create versions.
# Selected per Post/Book/Series by Record id (see Authored); one is the default.
class Author < ApplicationRecord
  include Recordable

  AVATAR_CONTENT_TYPES = %w[ image/jpeg image/png image/avif image/webp ]
  AVATAR_MAX_SIZE = 5.megabytes

  has_rich_text :bio
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_fill: [ 200, 200 ]
  end

  validates :name, presence: true
  validate :acceptable_avatar

  before_create :become_default_if_first
  after_save :demote_other_defaults, if: -> { default? && saved_change_to_default? }

  # The current version of every live (untrashed) author — mirrors Publishable#current.
  scope :current, -> { where(id: Record.active.where(recordable_type: name).select(:recordable_id)) }
  scope :ordered, -> { order(:name) }

  # A persona is public the instant it's saved and has no draft regime — edits
  # amend the current version in place; the world always sees the latest.
  def mutable? = true

  # The persona to preselect when composing — the marked default, else the first.
  def self.default
    current.find_by(default: true) || current.ordered.first
  end

  # name doubles as the slug title (Record#to_slug) and the avatar-helper name.
  def title = name
  def display_name = name

  def to_param = record.to_slug

  # Carry the bio + avatar forward on action-only versions (trash/restore) so a
  # restored persona doesn't come back blank — the same trick Comment uses.
  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.bio = bio.body unless changes.key?(:bio)
      version.avatar.attach(avatar.blob) if avatar.attached? && !changes.key?(:avatar)
    end
  end

  private
    def become_default_if_first
      self.default = true if Author.current.none?
    end

    def demote_other_defaults
      Author.current.where.not(record_id: record_id).update_all(default: false)
    end

    def acceptable_avatar
      return unless avatar.attached?

      unless avatar.blob.content_type.in?(AVATAR_CONTENT_TYPES)
        errors.add(:avatar, "must be a JPG, PNG, AVIF, or WebP image")
      end
      if avatar.blob.byte_size > AVATAR_MAX_SIZE
        errors.add(:avatar, "must be smaller than #{AVATAR_MAX_SIZE / 1.megabyte} MB")
      end
    end
end
