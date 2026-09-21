require "test_helper"

class ExportExpiryJobTest < ActiveJob::TestCase
  test "destroys exports past retention — record, row, and zip — and keeps fresh ones" do
    old = Export.request(accounts(:merovex), by: users(:alice)).tap(&:build!)
    blob = old.archive.blob
    old.update!(created_at: (Export::RETENTION + 1.day).ago)
    fresh = Current.with_account(accounts(:merovex)) { Export.request(accounts(:merovex), by: users(:alice)) }

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { ExportExpiryJob.perform_now }

    assert_not Export.exists?(old.id)
    assert_not Record.exists?(old.record_id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert Export.exists?(fresh.id)
  end
end
