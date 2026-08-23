require "test_helper"

# The send path's question, end to end: events in, sends skipped, lifts honored.
class PersonReputationTest < ActiveSupport::TestCase
  setup do
    @site = accounts(:merovex)
    @other = Account.create!(name: "Second Press", owner: users(:bob))
  end

  test "a hard bounce on one site blocks the next site from mailing the address" do
    here  = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    there = Current.with_account(@other) { Subscriber.create!(email_address: "reader@example.com", status: :confirmed) }
    assert_equal here.person, there.person

    DeliveryEvent.ingest!(provider: "ses", event: "hard_bounce", payload: {}, provider_message_id: "m1",
      recipient: "reader@example.com", delivery: nil)

    assert there.person.reputation.suppressed_for?(@other)
    assert here.reload.confirmed?, "no delivery to route to, so this site's row is untouched — the guard does the work"
  end

  test "a confirmation-email bounce (no delivery tags) still resolves the person and suppresses" do
    subscriber = Subscriber.opt_in(email_address: "typo@example.com")

    event = DeliveryEvent.ingest!(provider: "ses", event: "hard_bounce", payload: {}, provider_message_id: "m1",
      recipient: "Typo@Example.com")

    assert_equal subscriber.person, event.person
    assert subscriber.person.reputation.suppressed?
  end

  test "confirming lifts the global suppression and this site's own" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    Suppression.impose!(person: subscriber.person, reason: :hard_bounce)
    Suppression.impose!(person: subscriber.person, reason: :complaint, scope: @site)
    Suppression.impose!(person: subscriber.person, reason: :complaint, scope: @other)

    subscriber.confirm!

    reputation = subscriber.person.reputation
    assert_not reputation.suppressed_for?(@site)
    assert_not reputation.suppressed?, "proof of life lifts the global rows (the bounce and the escalated complaint)"
    assert reputation.suppressed_for?(@other), "the other site's own complaint stands"
    assert_equal %w[reconfirmed], Suppression.lifting.pluck(:reason).uniq
    assert_equal 2, Suppression.lifting.where(scope: nil).count
    assert_equal 1, Suppression.lifting.where(scope: @site).count
  end

  test "an admin's Reactivate lifts for this site only" do
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :bounced)
    Suppression.impose!(person: subscriber.person, reason: :hard_bounce)

    assert subscriber.reactivate!

    assert_not subscriber.person.reputation.suppressed_for?(@site)
    assert subscriber.person.reputation.suppressed_for?(@other)
    assert_equal "manual", Suppression.lifting.sole.reason
  end

  test "the delivery ledger outlives a purged subscriber, keyed to the person" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    event = DeliveryEvent.ingest!(provider: "ses", event: "hard_bounce", payload: {}, provider_message_id: "m1",
      recipient: "reader@example.com")
    person = subscriber.person

    subscriber.destroy

    assert DeliveryEvent.exists?(event.id)
    assert_equal person, event.reload.person
    assert_nil event.subscriber_id
    assert person.reputation.suppressed?
  end
end
