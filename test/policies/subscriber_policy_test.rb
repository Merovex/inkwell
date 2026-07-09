require "test_helper"

class SubscriberPolicyTest < ActiveSupport::TestCase
  test "manage is the domain admin's alone, with a reason on refusal" do
    assert SubscriberPolicy.new(users(:admin), Subscriber).manage?

    policy = SubscriberPolicy.new(users(:alice), Subscriber)
    assert_not policy.manage?
    assert_includes policy.failure_reasons, :not_admin
  end
end
