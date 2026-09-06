require "test_helper"

# The roster's headline. Counted from the consent log, so it has to agree with
# what the weekly digest reports about the same week.
class SubscriberMovementTest < ActiveSupport::TestCase
  setup { @account = accounts(:merovex) }

  def movement(now: Time.current) = SubscriberMovement.new(@account, now: now)

  test "sendable counts confirmed readers, not pending ones or seeds" do
    Subscriber.opt_in(email_address: "pending@example.com")
    Subscriber.opt_in(email_address: "reader@example.com").confirm!
    Subscriber.opt_in(email_address: "check@mail-tester.com").confirm!   # a seed

    assert_equal 1, movement.sendable
  end

  test "a BookFunnel arrival counts once, and a re-push doesn't count again" do
    Subscriber.opt_in_confirmed(email_address: "reader@example.com", source: "bookfunnel")
    Subscriber.opt_in_confirmed(email_address: "reader@example.com", source: "bookfunnel")

    assert_equal 1, movement.joined, "the partner's confirmed event is the arrival"
    assert_equal 1, movement.net
  end

  test "confirming a web opt-in counts at confirmation, not at the opt-in" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com", source: "nav")
    assert_equal 0, movement.joined, "a pending opt-in hasn't joined anything yet"

    subscriber.confirm!
    assert_equal 1, movement.joined
  end

  test "net is arrivals minus departures inside the window" do
    3.times { |i| Subscriber.opt_in(email_address: "reader#{i}@example.com").confirm! }
    Subscriber.find_by(email_address: "reader0@example.com").unsubscribe!

    assert_equal 3, movement.joined
    assert_equal 2, movement.net
  end

  test "arrivals older than thirty days fall out of the window" do
    travel_to 40.days.ago do
      Subscriber.opt_in(email_address: "old@example.com").confirm!
    end
    Subscriber.opt_in(email_address: "new@example.com").confirm!

    assert_equal 1, movement.joined
    assert_equal 2, movement.sendable, "still on the list, just not new"
  end

  test "departures count explicit opt-outs over ninety days, not bounces or complaints" do
    left = Subscriber.opt_in(email_address: "left@example.com")
    left.confirm!
    left.unsubscribe!
    dead = Subscriber.opt_in(email_address: "dead@example.com")
    dead.confirm!
    dead.mark_bounced!
    angry = Subscriber.opt_in(email_address: "angry@example.com")
    angry.confirm!
    angry.mark_complained!

    assert_equal 1, movement.departures, "a dead mailbox and a complaint aren't someone choosing to go"
  end

  test "a departure older than ninety days falls out of its window" do
    travel_to 100.days.ago do
      subscriber = Subscriber.opt_in(email_address: "long-gone@example.com")
      subscriber.confirm!
      subscriber.unsubscribe!
    end

    assert_equal 0, movement.departures
  end

  test "arrivals group by source, biggest first, with the partner's own name" do
    2.times { |i| Subscriber.opt_in_confirmed(email_address: "bf#{i}@example.com", source: "bookfunnel") }
    Subscriber.opt_in(email_address: "web@example.com", source: "nav").confirm!
    Subscriber.opt_in(email_address: "direct@example.com").confirm!

    assert_equal [ [ "BookFunnel", 2 ], [ "Direct", 1 ], [ "Nav", 1 ] ],
      movement.joined_by_source.sort_by { |source, count| [ -count, source ] }
  end

  test "a quiet month reports zero rather than blowing up" do
    assert_equal 0, movement.joined
    assert_equal 0, movement.net
    assert_equal 0, movement.departures
    assert_empty movement.joined_by_source
  end
end
