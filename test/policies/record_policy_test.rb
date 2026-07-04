require "test_helper"

class RecordPolicyTest < ActiveSupport::TestCase
  test "manage is creator or admin, with a reason on refusal" do
    assert RecordPolicy.new(users(:alice), records(:kickoff)).manage?
    assert RecordPolicy.new(users(:admin), records(:kickoff)).manage?

    policy = RecordPolicy.new(users(:bob), records(:kickoff))
    assert_not policy.manage?
    assert_includes policy.failure_reasons, :not_creator
  end

  test "view allows published content to all, drafts to creator and admin only" do
    assert RecordPolicy.new(users(:bob), records(:kickoff)).view?, "published is public"
    assert RecordPolicy.new(users(:bob), records(:welcome_comment)).view?, "comments have no publish regime"
    assert RecordPolicy.new(users(:alice), records(:typography)).view?
    assert RecordPolicy.new(users(:admin), records(:typography)).view?
    assert_not RecordPolicy.new(users(:bob), records(:typography)).view?
  end

  test "authorize! raises with the query, policy, and accumulated reasons" do
    error = assert_raises(ApplicationPolicy::NotAuthorizedError) do
      RecordPolicy.authorize!(users(:bob), records(:typography), :view)
    end

    assert_equal :view, error.query
    assert_equal RecordPolicy, error.policy
    assert_includes error.reasons, :unpublished
  end

  test "Scope resolves unpublished work to yours-only, everything for the admin" do
    drafts = Post.current.where.not(status: :published)

    assert_equal [ posts(:typography) ], RecordPolicy.scope_for(users(:alice), drafts).to_a
    assert_empty RecordPolicy.scope_for(users(:bob), drafts)
    assert_equal [ posts(:typography) ], RecordPolicy.scope_for(users(:admin), drafts).to_a
  end
end
