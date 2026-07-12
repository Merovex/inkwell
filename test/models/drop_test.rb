require "test_helper"

class DropTest < ActiveSupport::TestCase
  setup { @creator = users(:admin) }

  test "send_at_for is the stream's enrolled_at plus delay_days" do
    drop = new_drop(delay_days: 3)
    stream = Stream.new(enrolled_at: Time.utc(2026, 1, 1))

    assert_equal Time.utc(2026, 1, 4), drop.send_at_for(stream)
  end

  test "editing lands a new version and carries the body forward on trash" do
    drop = new_drop(delay_days: 0)
    record = drop.record

    record.revise(event: :updated, subject: "Changed", creator: @creator)
    record.trash

    assert_equal "Changed", record.reload.recordable.subject
    assert record.recordable.body.present?, "body carried forward on the action-only version"
    assert_equal 3, record.versions.count
  end

  test "requires subject and body" do
    drop = Drop.new(delay_days: 0, creator: @creator)

    assert_not drop.valid?
    assert drop.errors[:subject].any?
    assert drop.errors[:body].any?
  end

  private
    def new_drop(delay_days:)
      drip = Drip.new(title: "W", active: true, creator: @creator)
      Record.originate(drip)
      version = Drop.new(subject: "Hi", delay_days:, creator: @creator)
      version.body = "Hello there"
      Record.originate(version, parent: drip.record)
      version
    end
end
