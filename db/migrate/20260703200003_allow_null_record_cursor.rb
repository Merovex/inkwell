class AllowNullRecordCursor < ActiveRecord::Migration[8.2]
  # The record's recordable pointer is the "current version" cursor. Creation
  # order requires it to be briefly null: the record row must exist before the
  # first version can carry its record_id, then the cursor is set — all inside
  # one transaction. recordable_type stays null: false (the type is known at
  # creation); the unique index still guarantees one record per version.
  def change
    change_column_null :records, :recordable_id, true
  end
end
