require "test_helper"

# Boosts inside circles: the same tiny appreciations as the admin side, on
# messages/comments/answers, with a bell-only notification to the author.
class CircleBoostsTest < ActionDispatch::IntegrationTest
  setup do
    @circle = circles(:writers)
    @discussion = Current.with_bucket(@circle) do
      Record.originate(Message.new(title: "Cheer me", content: "words", creator: users(:alice),
        status: :published, published_at: Time.current))
    end
  end

  test "a member boosts a discussion; the author's bell rings, no email" do
    sign_in_as users(:bob)

    assert_difference -> { @discussion.boosts.count } => 1, -> { users(:alice).notifications.count } => 1 do
      post circle_record_boosts_path(@circle, @discussion), params: { boost: { content: "🔥" } }
    end
    notification = users(:alice).notifications.last
    assert_equal "boosted", notification.kind
    assert_match(/boosted your message: 🔥/, notification.title)
    assert_not_includes Notification::EMAILED, "boosted" # bell-only

    follow_redirect!
    assert_select ".boost", text: /🔥/
    # The palette is the house set.
    assert_select ".boosts__emoji", count: Boost::COMMON_EMOJIS.size
  end

  test "boosting your own record stays silent" do
    sign_in_as users(:alice)

    assert_no_difference -> { Notification.count } do
      post circle_record_boosts_path(@circle, @discussion), params: { boost: { content: "💯" } }
    end
  end

  test "removing a boost is yours-only, in its circle" do
    sign_in_as users(:bob)
    post circle_record_boosts_path(@circle, @discussion), params: { boost: { content: "👏" } }
    boost = @discussion.boosts.last

    assert_difference -> { @discussion.boosts.count }, -1 do
      delete circle_boost_path(@circle, boost)
    end
  end
end
