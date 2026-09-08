require "test_helper"

# Record::PurgeTrashJob — the nightly incineration of trash past its deadline.
# Every table that hangs off the stable Record identity must go with it, or
# SQLite's foreign keys stop the sweep dead (and one bad row blocks the rest).
class Record::PurgeTrashJobTest < ActiveSupport::TestCase
  setup do
    @creator = users(:admin)
    @drip = new_drip
    @drop = add_drop(subject: "Welcome", delay_days: 0, position: 1)
    @subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    @stream = @drip.enroll(@subscriber)
    @stream.advance!
  end

  test "purges a trashed drop that has already been delivered" do
    delivery = @stream.deliveries.sole
    trash_and_expire @drop.record

    assert_difference -> { DropDelivery.count } => -1, -> { Record.count } => -1 do
      Record::PurgeTrashJob.perform_now
    end
    assert_not DropDelivery.exists?(delivery.id)
  end

  test "purges a trashed drip, taking its drops and their deliveries with it" do
    trash_and_expire @drip.record

    assert_difference -> { DropDelivery.count } => -1, -> { Stream.count } => -1 do
      Record::PurgeTrashJob.perform_now
    end
    assert_empty Record.where(id: [ @drip.record_id, @drop.record_id ])
  end

  test "unstamps the delivery events of a purged delivery rather than orphaning them" do
    delivery = @stream.deliveries.sole
    event = DeliveryEvent.create!(provider: :postmark, event: :delivered, delivery: delivery,
      subscriber: @subscriber, payload: {})
    trash_and_expire @drop.record

    Record::PurgeTrashJob.perform_now

    assert_nil event.reload.delivery_id
  end

  test "reports a record it can't purge and carries on with the rest of the sweep" do
    later = add_drop(subject: "Second", delay_days: 1, position: 2)
    trash_and_expire @drop.record
    trash_and_expire later.record

    alerts = capturing_alerts do |captured|
      failing_to_destroy @drop.record_id do
        Record::PurgeTrashJob.perform_now
      end
      captured
    end

    assert Record.exists?(@drop.record_id), "the record that raised stays in trash for the next sweep"
    assert_not Record.exists?(later.record_id), "records after the failure still purge"
    assert_equal 1, alerts.size
    assert_equal @drop.record_id, alerts.sole.last[:context][:record_id]
  end

  private
    def trash_and_expire(record)
      record.trash
      record.update_columns(purge_after: 1.day.ago)
    end

    def new_drip
      version = Drip.new(title: "Welcome", active: true, creator: @creator)
      Record.originate(version)
      version
    end

    def add_drop(subject:, delay_days:, position:)
      version = Drop.new(subject:, delay_days:, creator: @creator)
      version.body = "<p>#{subject}</p>"
      Record.originate(version, parent: @drip.record)
      version.record.update!(position:)
      version
    end

    # Minitest 6 dropped the bundled mock library; swapping the method by hand
    # keeps this from needing a gem (same trick as CustomDomainStatusJobTest).
    def capturing_alerts
      captured = []
      original = Honeybadger.method(:notify)
      Honeybadger.define_singleton_method(:notify) { |message, **context| captured << [ message, context ] }
      yield captured
    ensure
      Honeybadger.define_singleton_method(:notify, original)
    end

    # Stands in for whatever a record's teardown can trip over — the missing
    # cleanup that produced the original fault, a callback, a vanished blob.
    def failing_to_destroy(record_id)
      Record.define_method(:destroy) do
        raise ActiveRecord::InvalidForeignKey, "FOREIGN KEY constraint failed" if id == record_id
        super()
      end
      yield
    ensure
      Record.remove_method(:destroy)
    end
end
