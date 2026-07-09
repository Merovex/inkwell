require "test_helper"

class SubscriberTest < ActiveSupport::TestCase
  test "opt_in creates a pending subscriber and logs the consent event" do
    subscriber = Subscriber.opt_in(email_address: " Reader@Example.COM ", source: "hero", ip: "1.2.3.4")

    assert subscriber.pending?
    assert_equal "reader@example.com", subscriber.email_address, "normalized"
    assert_equal "hero", subscriber.source
    assert_equal "1.2.3.4", subscriber.consent_ip
    assert_equal %w[subscribed], subscriber.events.pluck(:action)
  end

  test "opt_in dedupes by email onto the same row" do
    first = Subscriber.opt_in(email_address: "reader@example.com")
    again = Subscriber.opt_in(email_address: "reader@example.com")

    assert_equal first.id, again.id
    assert_equal 1, Subscriber.where(email_address: "reader@example.com").count
  end

  test "confirm flips to confirmed and appends the event" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!(ip: "1.2.3.4")

    assert subscriber.confirmed?
    assert subscriber.confirmed_at.present?
    assert_equal %w[subscribed confirmed], subscriber.events.pluck(:action)
  end

  test "opt_in is idempotent once confirmed — no state change, no event" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!

    Subscriber.opt_in(email_address: "reader@example.com")

    assert subscriber.reload.confirmed?
    assert_equal %w[subscribed confirmed], subscriber.events.pluck(:action)
  end

  test "re-subscribing after unsubscribe reuses the row and logs resubscribed" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!
    subscriber.unsubscribe!

    revived = Subscriber.opt_in(email_address: "reader@example.com")

    assert_equal subscriber.id, revived.id
    assert revived.pending?, "re-consent must go through double opt-in again"
    assert_equal %w[subscribed confirmed unsubscribed resubscribed], revived.events.pluck(:action)
  end

  test "confirmation and unsubscribe tokens resolve back to the subscriber" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")

    assert_equal subscriber, Subscriber.find_by_token_for(:confirmation, subscriber.generate_token_for(:confirmation))
    assert_equal subscriber, Subscriber.find_by_token_for(:unsubscribe, subscriber.generate_token_for(:unsubscribe))
  end

  test "a used confirmation token stops working once confirmed" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    token = subscriber.generate_token_for(:confirmation)
    subscriber.confirm!

    assert_nil Subscriber.find_by_token_for(:confirmation, token)
  end

  test "events are append-only" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    event = subscriber.events.first

    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(action: "confirmed") }
  end

  test "email address must be unique and well-formed" do
    Subscriber.create!(email_address: "reader@example.com")

    assert_not Subscriber.new(email_address: "reader@example.com").valid?
    assert_not Subscriber.new(email_address: "not-an-email").valid?
  end
end
