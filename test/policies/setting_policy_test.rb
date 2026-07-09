require "test_helper"

class SettingPolicyTest < ActiveSupport::TestCase
  test "manage is the domain admin's alone, with a reason on refusal" do
    setting = Setting.current

    assert SettingPolicy.new(users(:admin), setting).manage?

    policy = SettingPolicy.new(users(:alice), setting)
    assert_not policy.manage?
    assert_includes policy.failure_reasons, :not_admin
  end
end
