require "test_helper"

# Naming where readers come from, and the matching that attributes them.
class PromotionTest < ActiveSupport::TestCase
  test "a pasted landing-page URL is normalized down to its token" do
    promotion = Promotion.create!(creator: users(:alice), title: "October SFF", ref: "https://dl.bookfunnel.com/wzpbv5o1z2")
    assert_equal "wzpbv5o1z2", promotion.ref
  end

  test "a trailing slash and a query string don't change the token" do
    promotion = Promotion.create!(creator: users(:alice), title: "October SFF", ref: "https://dl.bookfunnel.com/wzpbv5o1z2/?utm_source=x")
    assert_equal "wzpbv5o1z2", promotion.ref
  end

  test "a bare code is taken as-is" do
    assert_equal "wzpbv5o1z2", Promotion.create!(creator: users(:alice), title: "October SFF", ref: "WZPBV5O1Z2").ref
  end

  test "a hyphenated token is allowed — a ref param is the generic case" do
    assert Promotion.new(creator: users(:alice), title: "A swap", ref: "october-swap").valid?
  end

  test "a token carrying a LIKE wildcard is rejected" do
    assert_not Promotion.new(creator: users(:alice), title: "Sneaky", ref: "a%b").valid?
    assert_not Promotion.new(creator: users(:alice), title: "Sneaky", ref: "a_b").valid?
  end

  test "a mistyped link is an error, not a promotion that quietly has none" do
    promotion = Promotion.new(creator: users(:alice), title: "Fat fingers", ref: "dl.book funnel/wzpbv")

    assert_not promotion.valid?
    assert_includes promotion.errors.full_messages.to_sentence, "recognize"
  end

  test "two promotions can't share a token" do
    Promotion.create!(creator: users(:alice), title: "October SFF", ref: "wzpbv5o1z2")
    duplicate = Promotion.new(creator: users(:alice), title: "Same link, different name", ref: "wzpbv5o1z2")

    assert_not duplicate.valid?
  end

  test "any number of promotions can have no token at all" do
    Promotion.create!(creator: users(:alice), title: "A swap with no link")
    assert Promotion.new(creator: users(:alice), title: "Another one").valid?
  end

  test "naming a promotion claims the readers who already arrived under its token" do
    early = subscriber_from("https://dl.bookfunnel.com/wzpbv5o1z2", email: "early@example.com")
    other = subscriber_from("https://dl.bookfunnel.com/s00a53gmdn", email: "other@example.com")

    promotion = Promotion.create!(creator: users(:alice), title: "October SFF", ref: "wzpbv5o1z2")

    assert_equal promotion, early.reload.promotion
    assert_nil other.reload.promotion
    # Claimed, not asserted — nobody attributed this by hand.
    assert_nil early.attributed_by
  end

  test "claiming leaves readers another promotion already holds alone" do
    reader = subscriber_from("https://dl.bookfunnel.com/wzpbv5o1z2")
    held = Promotion.create!(creator: users(:alice), title: "Named first", ref: "wzpbv5o1z2")
    assert_equal held, reader.reload.promotion

    # A second promotion whose ref matches the same URL fragment.
    Promotion.create!(creator: users(:alice), title: "Named second", ref: "wzpbv5o1z")

    assert_equal held, reader.reload.promotion
  end

  test "clearing a token claims nobody" do
    reader = subscriber_from("https://dl.bookfunnel.com/wzpbv5o1z2")
    promotion = Promotion.create!(creator: users(:alice), title: "Typo", ref: "nosuchtoken")
    assert_nil reader.reload.promotion

    promotion.update!(ref: nil)

    assert_nil reader.reload.promotion
  end

  test "destroying a promotion leaves its readers on the list, unattributed" do
    reader = subscriber_from("https://dl.bookfunnel.com/wzpbv5o1z2")
    promotion = Promotion.create!(creator: users(:alice), title: "October SFF", ref: "wzpbv5o1z2")
    assert_equal promotion, reader.reload.promotion

    assert_no_difference -> { Subscriber.count } do
      promotion.destroy
    end
    assert_nil reader.reload.promotion
  end

  test "unnamed refs count the arrivals nobody has named, biggest first" do
    2.times { |i| subscriber_from("https://dl.bookfunnel.com/wzpbv5o1z2", email: "a#{i}@example.com") }
    subscriber_from("https://dl.bookfunnel.com/s00a53gmdn", email: "b@example.com")

    assert_equal [ [ "wzpbv5o1z2", 2 ], [ "s00a53gmdn", 1 ] ], Promotion.unnamed_refs(accounts(:merovex))
  end

  test "a named ref drops off the unnamed list" do
    subscriber_from("https://dl.bookfunnel.com/wzpbv5o1z2")
    Promotion.create!(creator: users(:alice), title: "October SFF", ref: "wzpbv5o1z2")

    assert_empty Promotion.unnamed_refs(accounts(:merovex))
  end

  private
    def subscriber_from(source_url, email: "reader@example.com")
      Subscriber.opt_in_confirmed(email_address: email, source: "bookfunnel", source_url: source_url)
    end
end
