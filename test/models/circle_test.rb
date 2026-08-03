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

  test "a circle owns its board messages; an account owns none of them" do
    assert_includes circles(:writers).messages.map(&:title), "Welcome to the circle"
    assert_equal 0, accounts(:merovex).records.where(recordable_type: "CircleMessage").count
  end
end
