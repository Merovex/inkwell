require "test_helper"

class BulletinTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def originate_bulletin(title: "Sidebar changes", creator: users(:alice))
    bulletin = Bulletin.new(title: title, content: "<p>Here's what to expect.</p>",
      creator: creator, event: :created)
    Record.originate(bulletin)
    bulletin
  end

  test "a bulletin is a platform record — nil bucket allowed, others still require one" do
    bulletin = originate_bulletin
    assert_nil bulletin.record.bucket
    assert bulletin.record.valid?

    # Outside any account context a non-platform record has no bucket to
    # default to — and presence still gates it (the test harness pins
    # Current.account, so clear it for the negative case).
    Current.without_account do
      record = Record.new(recordable_type: "Post", creator: users(:alice))
      assert_not record.valid?
      assert record.errors[:bucket].any?
    end
  end

  test "first publish announces to every user except the author" do
    bulletin = originate_bulletin

    perform_enqueued_jobs(only: BulletinAnnounceJob) do
      bulletin.publish(creator: users(:alice))
    end

    recipients = Notification.where(kind: :bulletin_published).pluck(:user_id)
    assert_includes recipients, users(:bob).id
    assert_not_includes recipients, users(:alice).id

    notification = Notification.where(kind: :bulletin_published).first
    assert_equal "Announcement: Sidebar changes", notification.title
    assert_match %r{/bulletins/#{bulletin.record.id}}, notification.url
  end

  test "editing a published bulletin does not re-announce" do
    bulletin = originate_bulletin
    perform_enqueued_jobs(only: BulletinAnnounceJob) { bulletin.publish(creator: users(:alice)) }

    assert_no_difference -> { Notification.where(kind: :bulletin_published).count } do
      perform_enqueued_jobs(only: BulletinAnnounceJob) do
        bulletin.record.save_edit(creator: users(:alice), title: "Sidebar changes, revised")
      end
    end
  end

  test "a scheduled bulletin announces when the publish job fires" do
    bulletin = originate_bulletin
    bulletin.schedule(at: 2.hours.from_now, creator: users(:alice))
    assert_equal 0, Notification.where(kind: :bulletin_published).count

    travel 3.hours do
      # Sequential: the announce job is enqueued DURING the publish flush, so
      # one combined flush would miss it.
      perform_enqueued_jobs(only: Record::PublishLaterJob)
      perform_enqueued_jobs(only: BulletinAnnounceJob)
    end

    assert bulletin.record.reload.recordable.published?
    assert Notification.where(kind: :bulletin_published).exists?
  end
end
