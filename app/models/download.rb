# One redeemed fetch of a magnet file — created as a download POST 302s to
# the presigned URL. Grant present = the tokened claim flow (the rows are the
# counter behind Grant#exhausted?); grant absent = the ungated direct link.
# Either way the magnet is stamped, so per-magnet stats are one query.
# Append-only: created_at, no updates.
class Download < ApplicationRecord
  belongs_to :grant, optional: true
  belongs_to :magnet, default: -> { grant&.magnet }

  validates :format, inclusion: { in: Magnet::FORMATS }
end
