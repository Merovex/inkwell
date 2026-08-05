require "test_helper"

class CircleTest < ActiveSupport::TestCase
  test "create_with_owner seats the owner atomically" do
    circle = Circle.create_with_owner(name: "New Circle", owner: users(:bob))

    assert circle.persisted?
    assert circle.member?(users(:bob))
    assert_equal 1, circle.circle_memberships.count
    assert_equal "owner", circle.circle_memberships.first.role
  end

  test "member? is membership, never account ownership" do
    circle = circles(:writers)

    assert circle.member?(users(:alice)) # owner
    assert circle.member?(users(:bob))   # plain member
    assert_not circle.member?(users(:admin)) # root platform staff, but not a member
  end

  test "member_limit caps the seats (the owner's seat counts)" do
    circle = Circle.create_with_owner(name: "Tiny", owner: users(:alice), member_limit: 1)

    membership = circle.circle_memberships.create(user: users(:bob))
    assert_not membership.persisted?
    assert_match(/full/i, membership.errors.full_messages.to_sentence)
  end

  test "member_limit can never exceed the Dunbar hard cap" do
    circle = Circle.new(name: "Horde", owner: users(:alice), member_limit: Circle::MEMBER_HARD_CAP + 1)

    assert_not circle.valid?
    assert circle.errors[:member_limit].any?
  end

  test "no member_limit still means the Dunbar hard cap, not unlimited" do
    circle = circles(:writers)
    circle.update!(member_limit: nil)

    assert_equal Circle::MEMBER_HARD_CAP, circle.seat_cap
    assert_not circle.full?
  end

  test "a circle's discussions are Messages owned by the circle, isolated from any account" do
    circle = circles(:writers)

    # The circle's discussions are Messages, scoped to the circle bucket.
    assert_includes circle.messages.map(&:title), "Welcome to the circle"
    # Bucket isolation both ways: the forum's Messages aren't the circle's, and
    # the circle's discussion isn't the account's.
    assert_not_includes circle.messages.map(&:title), messages(:welcome).title
    assert_not_includes accounts(:merovex).messages.map(&:title), "Welcome to the circle"
  end
end
