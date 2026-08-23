require "test_helper"

class SubscriptionEventTest < ActiveSupport::TestCase
  test "fingerprint names the /24 neighborhood, not the address" do
    assert_equal SubscriptionEvent.fingerprint("203.0.113.7"), SubscriptionEvent.fingerprint("203.0.113.200")
    assert_not_equal SubscriptionEvent.fingerprint("203.0.113.7"), SubscriptionEvent.fingerprint("203.0.114.7")
  end

  test "fingerprint names the /56 for IPv6" do
    same  = SubscriptionEvent.fingerprint("2001:db8:abcd:1200::1")
    assert_equal same, SubscriptionEvent.fingerprint("2001:db8:abcd:12ff::beef")
    assert_not_equal same, SubscriptionEvent.fingerprint("2001:db8:abcd:1300::1")
  end

  test "fingerprint is keyed and never the raw IP" do
    digest = SubscriptionEvent.fingerprint("203.0.113.7")
    assert_match(/\A\h{64}\z/, digest)
    assert_not_equal OpenSSL::Digest::SHA256.hexdigest("203.0.113.0/24"), digest, "an unkeyed hash of a /24 is brute-forceable"
  end

  test "fingerprint is nil for blank or unparseable input" do
    assert_nil SubscriptionEvent.fingerprint(nil)
    assert_nil SubscriptionEvent.fingerprint("")
    assert_nil SubscriptionEvent.fingerprint("not-an-ip")
  end

  test "events stamp the fingerprint of their IP on create" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com", ip: "203.0.113.7")
    event = subscriber.events.last

    assert_equal "203.0.113.7", event.ip_address
    assert_equal SubscriptionEvent.fingerprint("203.0.113.7"), event.source_fingerprint
  end

  test "an event with no IP has no fingerprint" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    assert_nil subscriber.events.last.source_fingerprint
  end
end
