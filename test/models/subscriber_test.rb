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

  test "re-subscribing after a hard bounce revives the row through double opt-in" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!
    subscriber.mark_bounced!(source: "postmark")

    revived = Subscriber.opt_in(email_address: "reader@example.com")

    assert_equal subscriber.id, revived.id
    assert revived.pending?, "a bounced address must re-prove deliverability via double opt-in"
    assert_equal %w[subscribed confirmed bounced resubscribed], revived.events.pluck(:action)
  end

  test "a complaint is the strongest suppression — overrides others, never downgraded" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!
    subscriber.unsubscribe!

    subscriber.mark_complained!(source: "postmark")
    assert subscriber.complained?, "a complaint outranks an opt-out"

    subscriber.unsubscribe!
    subscriber.mark_bounced!(source: "postmark")
    assert subscriber.complained?, "neither opt-out nor bounce downgrades a complaint"
  end

  test "re-subscribing after a complaint revives the row through double opt-in" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!
    subscriber.mark_complained!(source: "ses")

    revived = Subscriber.opt_in(email_address: "reader@example.com")

    assert_equal subscriber.id, revived.id
    assert revived.pending?, "fresh consent must go through double opt-in again"
    assert_equal %w[subscribed confirmed complained resubscribed], revived.events.pluck(:action)
  end

  test "confirmation and unsubscribe tokens resolve back to the subscriber" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")

    assert_equal subscriber, Subscriber.find_by_token_for(:confirmation, subscriber.generate_token_for(:confirmation))
    assert_equal subscriber, Subscriber.find_by_token_for(:unsubscribe, subscriber.generate_token_for(:unsubscribe))
  end

  test "the confirmation token stays valid after confirming, and confirm! is idempotent" do
    # The token deliberately does NOT fold in confirmed_at: a scanner prefetch
    # that confirms first must not leave the human's click with a dead link.
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    token = subscriber.generate_token_for(:confirmation)
    subscriber.confirm!

    assert_equal subscriber, Subscriber.find_by_token_for(:confirmation, token)
    assert_nothing_raised { subscriber.confirm! }
    assert subscriber.reload.confirmed?
  end

  test "events are append-only" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    event = subscriber.events.first

    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(action: "confirmed") }
  end

  test "one membership per person per press; same address on another press is fine" do
    Subscriber.create!(email_address: "reader@example.com")

    assert_not Subscriber.new(email_address: "reader@example.com").valid?

    other = Account.create!(name: "Other Press", owner: users(:bob))
    assert Current.with_account(other) { Subscriber.create!(email_address: "reader@example.com") }.persisted?
    assert_equal 1, Person.where(email_address: "reader@example.com").count
  end

  test "email address must be well-formed" do
    assert_not Subscriber.new(email_address: "not-an-email").valid?
  end

  test "disposable domains are rejected at creation" do
    assert_not Subscriber.new(email_address: "burner@mailinator.com").valid?
    assert_not Subscriber.new(email_address: "burner@yopmail.com").valid?
  end

  test "reserved TLDs are rejected at creation" do
    %w[ a@b.test a@b.invalid a@b.localhost a@b.example ].each do |address|
      assert_not Subscriber.new(email_address: address).valid?, "#{address} should be invalid"
    end
  end

  test "plus-addressing is a real reader, not a threat" do
    assert Subscriber.new(email_address: "reader+inkwell@example.com").valid?
  end

  test "hygiene checks are create-only: a later blocklisted address can still unsubscribe" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.update_columns(email_address: "burner@mailinator.com")  # grandfathered row from before the blocklist

    assert_nothing_raised { subscriber.unsubscribe! }
    assert subscriber.unsubscribed?
  end

  test "seed domains subscribe fine but land flagged, including subdomain inboxes" do
    seed = Subscriber.opt_in(email_address: "daughter.park.neck@aboutmy.email")
    assert seed.pending?, "a seed goes through normal double opt-in"
    assert seed.seed?

    assert Subscriber.opt_in(email_address: "report@abc123.mailosaur.net").seed?
    assert Subscriber.opt_in(email_address: "check@mail-tester.com").seed?,
      "seeds on the gem's disposable list must still get through (allow list)"
    assert_not Subscriber.opt_in(email_address: "reader@example.com").seed?
  end

  test "seeds are not readers and never sendable" do
    seed = Subscriber.opt_in(email_address: "check@mail-tester.com")
    seed.confirm!
    reader = Subscriber.opt_in(email_address: "reader@example.com")
    reader.confirm!

    assert_not_includes Subscriber.readers, seed
    assert_not_includes Subscriber.sendable, seed
    assert_includes Subscriber.sendable, reader
  end

  test "rejection_reason names the layer that caught the address" do
    assert_equal "format", Subscriber.rejection_reason("not-an-email")
    assert_equal "reserved_tld", Subscriber.rejection_reason("a@b.test")
    assert_equal "disposable", Subscriber.rejection_reason("burner@mailinator.com")
    assert_nil Subscriber.rejection_reason("reader@example.com")
    assert_nil Subscriber.rejection_reason("check@mail-tester.com"), "allow-listed seeds aren't 'disposable'"
  end

  # ── opt_in_confirmed: a partner's pre-consented push (BookFunnel) ──────────

  # This path must send nothing; the mailer assertions live in ActionMailer's
  # helper, which the model case doesn't carry by default.
  include ActionMailer::TestHelper

  test "opt_in_confirmed lands confirmed, with both consent events and the evidence" do
    subscriber = Subscriber.opt_in_confirmed(
      email_address: " Reader@Example.COM ", source: "bookfunnel", ip: "103.219.21.105",
      country_code: "GB", gdpr_country: true, source_url: "https://dl.bookfunnel.com/the-bargain"
    )

    assert subscriber.confirmed?, "the partner already confirmed and holds the consent"
    assert subscriber.confirmed_at
    assert_equal "reader@example.com", subscriber.email_address, "normalized"
    assert_equal "bookfunnel", subscriber.source
    assert_equal "103.219.21.105", subscriber.consent_ip
    assert_equal "GB", subscriber.country_code
    assert subscriber.gdpr_country
    assert_equal "https://dl.bookfunnel.com/the-bargain", subscriber.source_url
    assert_equal %w[subscribed confirmed], subscriber.events.pluck(:action)
  end

  test "opt_in_confirmed sends no confirmation email and is idempotent" do
    assert_no_enqueued_emails do
      first = Subscriber.opt_in_confirmed(email_address: "reader@example.com", source: "bookfunnel")
      again = Subscriber.opt_in_confirmed(email_address: "reader@example.com", source: "bookfunnel")

      assert_equal first.id, again.id
      assert_equal %w[subscribed confirmed], again.events.pluck(:action), "no second consent event"
    end
  end

  test "opt_in_confirmed starts the drips, and never for a seed inbox" do
    drip = Drip.new(title: "Welcome", trigger: "confirmed", active: true, creator: users(:admin))
    Record.originate(drip)

    reader = Subscriber.opt_in_confirmed(email_address: "reader@example.com", source: "bookfunnel")
    assert_equal 1, reader.streams.count, "a confirmed reader enrolls, same as a clicked confirmation"

    seed = Subscriber.opt_in_confirmed(email_address: "check@mail-tester.com", source: "bookfunnel")
    assert seed.seed?
    assert_empty seed.streams, "a diagnostic inbox joins the list but runs no campaign"
  end

  test "opt_in_confirmed refuses to revive anyone who opted out here" do
    %i[unsubscribe! mark_complained! mark_bounced!].each_with_index do |departure, index|
      email = "reader#{index}@example.com"
      subscriber = Subscriber.opt_in(email_address: email)
      subscriber.confirm!
      subscriber.public_send(departure)
      was = subscriber.status

      assert_nil Subscriber.opt_in_confirmed(email_address: email, source: "bookfunnel"),
        "a partner's word cannot undo a withdrawal made here"
      assert_equal was, subscriber.reload.status
    end
  end

  test "opt_in_confirmed leaves suppressions standing, where confirm! lifts them" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    Suppression.impose!(person: subscriber.person, reason: :hard_bounce)

    Subscriber.opt_in_confirmed(email_address: "reader@example.com", source: "bookfunnel")

    assert subscriber.reload.confirmed?
    assert Suppression.in_force_for.exists?(person: subscriber.person),
      "nothing in a partner's payload proves the mailbox is alive again"
  end
end
