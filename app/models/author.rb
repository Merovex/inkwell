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
  # A dedicated hero portrait, distinct from the bio avatar: the hero shows
  # this when set (data-hero-art=portrait) and falls back to the avatar, so a
  # small headshot can stay the bio photo while the hero runs a bigger image.
  has_one_attached :hero_image

  validates :name, presence: true
  # A one-line hook shown under the name in the author grid — kept short so
  # it reads as a tagline, not a second bio.
  validates :tagline, length: { maximum: 140 }, allow_blank: true
  validate :acceptable_avatar
  validate :acceptable_hero_image

  before_create :become_default_if_first
  after_save :demote_other_defaults, if: -> { default? && saved_change_to_default? }

  # The current version of every live (untrashed) author — mirrors Publishable#current.
  scope :current, -> { where(id: Record.active.where(recordable_type: name).select(:recordable_id)) }
  scope :ordered, -> { order(:name) }

  # A persona is public the instant it's saved and has no draft regime — edits
  # amend the current version in place; the world always sees the latest.
  def mutable? = true

  # name doubles as the slug title (Record#to_slug) and the avatar-helper name.
  def title = name
  def display_name = name

  def to_param = record.to_slug

  # The public page uses a pretty name-based slug (/authors/troy-buzby) rather
  # than the id-first form — personas are few, always-live, and the name is the
  # brand. Admin routes keep to_param's id-first slug; AuthorsController still
  # resolves legacy id-first public links and 301s them to this.
  def public_slug = name.parameterize

  # Carry the bio + images forward on action-only versions (trash/restore) so a
  # restored persona doesn't come back blank — the same trick Comment uses.
  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.bio = bio.body unless changes.key?(:bio)
      version.avatar.attach(avatar.blob) if avatar.attached? && !changes.key?(:avatar)
      version.hero_image.attach(hero_image.blob) if hero_image.attached? && !changes.key?(:hero_image)
    end
  end

  private
    # Default-flag maintenance is per-account: the first persona in an account
    # becomes its default, and marking one demotes only its account's others
    # (Current.account covers the pre-record create).
    def become_default_if_first
      self.default = true if owning_account.authors.none?
    end

    def demote_other_defaults
      owning_account.authors.where.not(record_id: record_id).update_all(default: false)
    end

    def owning_account
      record&.account || Current.account
    end

    def acceptable_avatar = acceptable_image(:avatar)
    def acceptable_hero_image = acceptable_image(:hero_image)

    # Same content-type/size gate for both the avatar and the hero image.
    def acceptable_image(field)
      attachment = public_send(field)
      return unless attachment.attached?

      unless attachment.blob.content_type.in?(AVATAR_CONTENT_TYPES)
        errors.add(field, "must be a JPG, PNG, AVIF, or WebP image")
      end
      if attachment.blob.byte_size > AVATAR_MAX_SIZE
        errors.add(field, "must be smaller than #{AVATAR_MAX_SIZE / 1.megabyte} MB")
      end
    end
end
