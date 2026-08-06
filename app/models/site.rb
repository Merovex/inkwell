# The public site's identity — name, tagline, About blurb, legal pages, logo.
# One per account, a recordable on the spine (versioned like everything else),
# reached through Account#site and edited from /admin/settings. Replaces the
# old install-wide Setting singleton (ADR 0017 / plan 1.5).
#
# Like Author: always-live, no draft regime — edits amend the current version
# in place. contact_email lives on the account (1.1); the delegation keeps the
# settings form and the mailers' reply_to reading one object.
class Site < ApplicationRecord
  include Recordable

  LOGO_CONTENT_TYPES = %w[ image/jpeg image/png image/avif image/webp image/svg+xml ]
  LOGO_MAX_SIZE = 5.megabytes

  # The About blurb — rich text so it can carry formatting on the About page;
  # its plain-text form feeds the public <meta description>.
  has_rich_text :description

  # Legal pages, admin-authored rich text (cookies live inside the privacy copy).
  has_rich_text :privacy_policy
  has_rich_text :terms

  # The public logo; absent means the built-in wordmark (see the public layout).
  has_one_attached :logo

  # The hero banner (the SiteDesigner's "Banner image" hero background);
  # absent, that background option just shows its legibility wash.
  has_one_attached :banner

  # The hero's foreground image for the "Custom image" hero art (data-hero-art=
  # image): the author's own picture beside the copy, instead of a book cover
  # or the author portrait. Uploaded in the designer's hero pane.
  has_one_attached :hero_image

  # The signup band's own backdrop (the newsletter Photo presentation);
  # absent, the band falls back to the author photo.
  has_one_attached :newsletter_photo

  validates :site_name, presence: true
  validate :acceptable_images

  delegate :contact_email, :contact_email=, to: :account, allow_nil: true
  # The handle (the account's Kindred Quill name: platform URL + shared-lane
  # From) rides the same settings form the same way.
  delegate :handle, :handle=, to: :account, allow_nil: true

  # Mutable: edits amend in place, so the Record-level rebuild trigger never
  # fires — the static site rebuilds from here instead.
  after_update_commit -> { SiteBuildJob.schedule(record.bucket) if record&.bucket_type == "Account" }

  def mutable? = true

  # A Site is only ever an Account's (the press's public identity), so its
  # bucket is that Account.
  def account = record&.bucket

  def title = site_name

  private
    def acceptable_images
      %i[ logo banner hero_image newsletter_photo ].each { |name| acceptable_image(name) }
    end

    def acceptable_image(name)
      attachment = public_send(name)
      return unless attachment.attached?

      unless attachment.blob.content_type.in?(LOGO_CONTENT_TYPES)
        errors.add(name, "must be a JPG, PNG, AVIF, WebP, or SVG image")
      end
      if attachment.blob.byte_size > LOGO_MAX_SIZE
        errors.add(name, "must be smaller than #{LOGO_MAX_SIZE / 1.megabyte} MB")
      end
    end
end
