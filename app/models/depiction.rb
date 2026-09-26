# A shareable cover-image owner, the visual sibling of Body. Book versions
# reference a depiction by id (books.depiction_id), and a new depiction is
# minted only when the cover actually changes — action-only or text-only
# versions point at the previous one. Destroying it purges the attached image.
class Depiction < ApplicationRecord
  # Only images a browser can show and the variant pipeline can process;
  # anything else used to be accepted here and then fail in the variant job.
  COVER_CONTENT_TYPES = %w[ image/jpeg image/png image/webp image/avif image/gif ].freeze

  # The public cover slot renders at ~220px wide, so a 480px-wide WebP covers it
  # crisply on 2× displays at a fraction of the old 600px JPG's bytes.
  # process: :later builds it in a job at upload time, so a visitor's request
  # is never the one that triggers (slow, synchronous) variant generation.
  # (Was preprocessed: true, deprecated in Rails 8.2 and gone in 9.0 — :later
  # is what that option resolved to.)
  has_one_attached :image do |attachable|
    attachable.variant :cover, resize_to_limit: [ 480, 720 ], format: :webp, process: :later
    attachable.variant :thumb, resize_to_limit: [ 256, 256 ], format: :webp
  end

  validate :image_is_a_picture

  private
    def image_is_a_picture
      return unless image.attached?

      errors.add(:image, "must be a JPG, PNG, WebP, AVIF, or GIF image") unless image.blob.content_type.in?(COVER_CONTENT_TYPES)
    end
end
