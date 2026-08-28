# One redeemed fetch of a magnet file — created as the download POST 302s to
# the presigned URL. The rows are both the counter behind Grant#exhausted? and
# the audit trail (who pulled which format, when). Append-only: created_at,
# no updates.
class Download < ApplicationRecord
  belongs_to :grant

  validates :format, inclusion: { in: Magnet::FORMATS }
end
