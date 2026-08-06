# Platform records (docs: Bulletin — announcements from root staff to every
# user) belong to no Account or Circle: the bucket goes nullable and Record
# validates presence for everything except the platform types.
class AllowPlatformRecords < ActiveRecord::Migration[8.1]
  def change
    change_column_null :records, :bucket_type, true
    change_column_null :records, :bucket_id, true
  end
end
