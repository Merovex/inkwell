# Install-wide configuration, modelled as a singleton — one row for the whole
# install, always reached through Setting.current. Today it carries the public
# Merovex Press identity (name, tagline, about blurb, contact, logo); more
# sections slot in as columns/attachments later. Managed only by a domain_admin
# (see AdminOnly) from /admin/settings.
class Setting < ApplicationRecord
  LOGO_CONTENT_TYPES = %w[ image/jpeg image/png image/avif image/webp image/svg+xml ]
  LOGO_MAX_SIZE = 5.megabytes

  # The About blurb — rich text so it can carry formatting on a future About
  # page; its plain-text form feeds the public <meta description>.
  has_rich_text :description

  # Legal pages, admin-authored rich text (cookies live inside the privacy copy).
  has_rich_text :privacy_policy
  has_rich_text :terms

  # The public logo; absent means the built-in Merovex wordmark (see the
  # public layout's brand).
  has_one_attached :logo

  validates :site_name, presence: true
  validate :acceptable_logo

  # Read on every public request (layout identity + the show-page etag), so it's
  # cached and self-busts on any change (the admin form is the only writer).
  CACHE_KEY = "setting".freeze
  after_commit -> { Rails.cache.delete(CACHE_KEY) }

  # The one and only settings row, created with the shipped defaults on first
  # read so the public site reads identically until an admin edits it.
  def self.current
    Rails.cache.fetch(CACHE_KEY) do
      first || create!(
        site_name: "Merovex Press",
        tagline: "Stories where humans meet the impossible",
        contact_email: "hello@merovex.press"
      )
    end
  end

  private
    def acceptable_logo
      return unless logo.attached?

      unless logo.blob.content_type.in?(LOGO_CONTENT_TYPES)
        errors.add(:logo, "must be a JPG, PNG, AVIF, WebP, or SVG image")
      end
      if logo.blob.byte_size > LOGO_MAX_SIZE
        errors.add(:logo, "must be smaller than #{LOGO_MAX_SIZE / 1.megabyte} MB")
      end
    end
end
