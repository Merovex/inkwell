# A shareable cover-image owner, the visual sibling of Body. Book versions
# reference a depiction by id (books.depiction_id), and a new depiction is
# minted only when the cover actually changes — action-only or text-only
# versions point at the previous one. Destroying it purges the attached image.
class Depiction < ApplicationRecord
  # The public cover slot renders at ~220px wide, so a 480px-wide WebP covers it
  # crisply on 2× displays at a fraction of the old 600px JPG's bytes.
  # preprocessed: true builds it in a job at upload time, so a visitor's request
  # is never the one that triggers (slow, synchronous) variant generation.
  has_one_attached :image do |attachable|
    attachable.variant :cover, resize_to_limit: [ 480, 720 ], format: :webp, preprocessed: true
    attachable.variant :thumb, resize_to_limit: [ 256, 256 ], format: :webp
  end
end
