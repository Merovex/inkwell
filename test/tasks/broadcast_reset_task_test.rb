require "test_helper"
require "rake"

class BroadcastResetTaskTest < ActiveSupport::TestCase
  setup do
    Inkwell::Application.load_tasks unless Rake::Task.task_defined?("broadcast:reset")
    Rake::Task["broadcast:reset"].reenable
    @record = records(:kickoff)
    @subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
  end

  teardown do
    ENV.delete("RECORD_ID")
  end

  test "clears a stuck broadcast and its deliveries so the post can be sent again" do
    broadcast = @record.create_broadcast!
    broadcast.deliveries.create!(subscriber: @subscriber)

    ENV["RECORD_ID"] = @record.id.to_s
    capture_io { Rake::Task["broadcast:reset"].invoke }

    assert_nil @record.reload.broadcast
    assert_empty BroadcastDelivery.where(broadcast_id: broadcast.id)
  end

  test "refuses to reset once any delivery has been sent — that would double-mail" do
    broadcast = @record.create_broadcast!
    broadcast.deliveries.create!(subscriber: @subscriber, sent_at: Time.current)

    ENV["RECORD_ID"] = @record.id.to_s
    assert_raises(SystemExit) { capture_io { Rake::Task["broadcast:reset"].invoke } }

    assert_equal broadcast, @record.reload.broadcast
  end

  test "refuses to reset a completed broadcast" do
    @record.create_broadcast!(sent_at: Time.current)

    ENV["RECORD_ID"] = @record.id.to_s
    assert_raises(SystemExit) { capture_io { Rake::Task["broadcast:reset"].invoke } }

    assert_not_nil @record.reload.broadcast
  end

  test "requires a record id" do
    assert_raises(SystemExit) { capture_io { Rake::Task["broadcast:reset"].invoke } }
  end
end
