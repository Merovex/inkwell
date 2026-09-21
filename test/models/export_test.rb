require "test_helper"

class ExportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  test "requesting an export originates a record in the account and queues the build" do
    export = nil
    assert_enqueued_with(job: ExportJob) { export = Export.request(accounts(:merovex), by: users(:alice)) }

    assert export.pending?
    assert_equal accounts(:merovex), export.account
    assert_equal users(:alice), export.record.creator
    assert_includes accounts(:merovex).exports, export
  end

  test "a second request while one is building is refused; a stalled one doesn't block" do
    first = Export.request(accounts(:merovex), by: users(:alice))
    assert_nil Export.request(accounts(:merovex), by: users(:alice))

    first.update!(created_at: 2.hours.ago)
    assert Export.request(accounts(:merovex), by: users(:alice)), "a pending row past STALLED_AFTER lost its worker"
  end

  test "build! attaches the zip, stamps the row, and emails the requester" do
    export = Export.request(accounts(:merovex), by: users(:alice))

    assert_enqueued_emails(1) { export.build! }

    assert export.built?
    assert export.completed_at.present?
    assert export.archive.attached?
    assert_equal "application/zip", export.archive.content_type
    assert_match(/-export-\d{4}-\d{2}-\d{2}\.zip\z/, export.archive.filename.to_s)
    assert export.downloadable?
  end

  test "a failed build is stamped on the row and re-raised" do
    export = Export.request(accounts(:merovex), by: users(:alice))
    original = Export::Archive.method(:new)
    broken = Object.new.tap { |fake| fake.define_singleton_method(:build) { raise "disk full" } }
    Export::Archive.define_singleton_method(:new) { |*| broken }

    assert_raises(RuntimeError) { export.build! }
    assert export.reload.failed?
    assert_not export.downloadable?
  ensure
    Export::Archive.define_singleton_method(:new, original)
  end

  test "an export stops being downloadable after RETENTION" do
    export = Export.request(accounts(:merovex), by: users(:alice))
    export.build!

    travel Export::RETENTION + 1.minute do
      assert_not export.downloadable?
      assert_includes Export.expired, export
    end
  end

  test "record_download! counts the fetch" do
    export = Export.request(accounts(:merovex), by: users(:alice))
    export.record_download!

    assert_equal 1, export.reload.downloads_count
    assert export.last_downloaded_at.present?
  end
end
