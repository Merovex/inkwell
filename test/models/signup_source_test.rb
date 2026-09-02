require "test_helper"

class SignupSourceTest < ActiveSupport::TestCase
  test "a consent event with an IP leaves an identity-free trace on the platform" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com", source: "hero", ip: "203.0.113.7")
    event = subscriber.events.last
    trace = SignupSource.last

    assert_equal event.source_fingerprint, trace.source_fingerprint
    assert_equal "subscribed", trace.action
    assert_equal subscriber.account, trace.account
    assert_equal event.created_at, trace.created_at
    assert_equal %w[account_id action created_at id source_fingerprint], SignupSource.column_names.sort,
      "the residue must never grow a column that names a reader"
  end

  test "an event with no IP leaves no trace" do
    assert_no_difference -> { SignupSource.count } do
      Subscriber.opt_in(email_address: "reader@example.com")
    end
  end

  test "the same neighborhood on two sites shares one fingerprint" do
    Subscriber.opt_in(email_address: "one@example.com", ip: "203.0.113.7")
    other = Account.create!(name: "Second Press", owner: users(:bob))
    Current.with_account(other) { Subscriber.opt_in(email_address: "two@example.com", ip: "203.0.113.99") }

    traces = SignupSource.order(:id).last(2)
    assert_equal [ accounts(:merovex), other ], traces.map(&:account)
    assert_equal 1, traces.map(&:source_fingerprint).uniq.size
  end

  test "traces are append-only" do
    Subscriber.opt_in(email_address: "reader@example.com", ip: "203.0.113.7")
    assert_raises(ActiveRecord::ReadOnlyRecord) { SignupSource.last.update!(action: "confirmed") }
  end
end
