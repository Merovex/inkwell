# A shareable cover-image owner, the visual sibling of Body. Book versions
# reference a depiction by id (books.depiction_id), and a new depiction is
# minted only when the cover actually changes — action-only or text-only
# versions point at the previous one. Destroying it purges the attached image.
class Depiction < ApplicationRecord
  has_one_attached :image do |attachable|
    attachable.variant :cover, resize_to_limit: [ 600, 900 ]
    attachable.variant :thumb, resize_to_limit: [ 256, 256 ]
  end
end
