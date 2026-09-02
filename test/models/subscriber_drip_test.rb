require "test_helper"

# Confirmation is the drip trigger; unsubscribe ends any in-flight run.
class SubscriberDripTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @drip = Drip.new(title: "Welcome", active: true, creator: users(:admin))
    Record.originate(@drip)
  end

  test "confirming enrolls into active drips and enqueues an advance" do
    sub = Subscriber.create!(email_address: "reader@example.com")  # pending

    assert_enqueued_with(job: DripAdvanceJob) { sub.confirm! }

    assert_equal [ @drip.record_id ], sub.streams.pluck(:drip_record_id)
  end

  test "confirming a seed enrolls nothing — the confirmation email is its whole job" do
    seed = Subscriber.create!(email_address: "report@aboutmy.email")

    assert_no_enqueued_jobs(only: DripAdvanceJob) { seed.confirm! }

    assert seed.confirmed?
    assert_empty seed.streams
  end

  test "unsubscribing ends in-flight streams" do
    sub = Subscriber.create!(email_address: "reader@example.com")
    sub.confirm!
    assert sub.streams.active.exists?

    sub.unsubscribe!

    assert_not sub.streams.active.exists?
    assert_equal "unsubscribed", sub.streams.first.ended_reason
  end
end
