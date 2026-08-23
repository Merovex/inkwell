require "test_helper"

# The cross-site suppression ledger (ADR 0027): what imposes, what lifts, and
# what Person::Reputation reads back for a given site.
class SuppressionTest < ActiveSupport::TestCase
  setup do
    @site = accounts(:merovex)
    @other = Account.create!(name: "Second Press", owner: users(:bob))
    @person = Person.create!(email_address: "reader@example.com")
  end

  test "a hard bounce suppresses the person for every site" do
    Suppression.impose!(person: @person, reason: :hard_bounce)

    assert @person.reputation.suppressed?
    assert @person.reputation.suppressed_for?(@site)
    assert @person.reputation.suppressed_for?(@other)
  end

  test "a complaint suppresses only the site that sent the mail" do
    Suppression.impose!(person: @person, reason: :complaint, scope: @site)

    assert_not @person.reputation.suppressed?
    assert @person.reputation.suppressed_for?(@site)
    assert_not @person.reputation.suppressed_for?(@other)
  end

  test "complaints against ESCALATE_AFTER distinct sites go global" do
    Suppression.impose!(person: @person, reason: :complaint, scope: @site)
    assert_not @person.reputation.suppressed?

    Suppression.impose!(person: @person, reason: :complaint, scope: @other)
    assert @person.reputation.suppressed?, "two sites complained about"
    assert Suppression.imposing.complaint.where(person: @person, scope: nil).exists?
  end

  test "an unattributed complaint is global" do
    Suppression.impose!(person: @person, reason: :complaint, scope: nil)
    assert @person.reputation.suppressed?
  end

  test "imposing the same suppression twice writes one row" do
    assert_difference -> { Suppression.count }, 1 do
      Suppression.impose!(person: @person, reason: :hard_bounce)
      Suppression.impose!(person: @person, reason: :hard_bounce)
    end
  end

  test "a global lift frees every site and is itself a row" do
    Suppression.impose!(person: @person, reason: :hard_bounce)

    lifts = Suppression.lift!(person: @person, reason: :reconfirmed)

    assert_equal 1, lifts.size
    assert lifts.first.lift?
    assert_equal "hard_bounce", lifts.first.lifted.reason
    assert_not @person.reputation.suppressed?
    assert_not @person.reputation.suppressed_for?(@other)
    assert_equal 2, Suppression.count, "history kept"
  end

  test "a site-scoped lift of a global suppression frees that site alone" do
    Suppression.impose!(person: @person, reason: :hard_bounce)

    Suppression.lift!(person: @person, reason: :manual, scope: @site)

    assert_not @person.reputation.suppressed_for?(@site)
    assert @person.reputation.suppressed_for?(@other), "the other site is still bound by the global row"
    assert @person.reputation.suppressed?, "the global list itself is untouched"
  end

  test "a new hard bounce after a lift binds again" do
    Suppression.impose!(person: @person, reason: :hard_bounce)
    Suppression.lift!(person: @person, reason: :reconfirmed)
    Suppression.impose!(person: @person, reason: :hard_bounce)

    assert @person.reputation.suppressed?
  end

  test "lifting with nothing in force writes nothing" do
    assert_empty Suppression.lift!(person: @person, reason: :reconfirmed)
  end

  test "rows are append-only and reasons match their polarity" do
    row = Suppression.impose!(person: @person, reason: :hard_bounce)
    assert_raises(ActiveRecord::ReadOnlyRecord) { row.update!(reason: "complaint") }

    assert_not Suppression.new(person: @person, reason: "reconfirmed").valid?, "reconfirmed only lifts"
    assert_not Suppression.new(person: @person, reason: "hard_bounce", lifted: row).valid?, "a bounce never lifts"
  end

  test "rebuild! replays the ledgers in time order" do
    subscriber = Subscriber.opt_in(email_address: @person.email_address)
    DeliveryEvent.ingest!(provider: "ses", event: "hard_bounce", payload: {}, provider_message_id: "m1",
      recipient: @person.email_address, occurred_at: 2.days.ago)
    assert @person.reputation.suppressed?

    travel_to 1.day.ago do
      subscriber.confirm!   # proof of life, after the bounce
    end
    assert_not @person.reputation.suppressed?

    Suppression.delete_all
    Suppression.rebuild!

    assert_equal 2, Suppression.count, "one imposition, one lift"
    assert_not @person.reputation.suppressed?
    assert_equal [ "hard_bounce", "reconfirmed" ], Suppression.order(:created_at).pluck(:reason)
  end
end
