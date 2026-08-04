# Record-general view helpers. `record_show_path` resolves a record's admin
# page from its delegated type (admin_post_path, admin_book_path, …), so shared
# UI (the archive control, archived lists) stays parent-agnostic — the same
# trick CommentsHelper uses for comment parents.
module RecordsHelper
  def record_show_path(record, **options)
    public_send(:"admin_#{record.recordable_name}_path", record, **options)
  end
end
