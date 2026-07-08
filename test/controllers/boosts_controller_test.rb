require "test_helper"

class BoostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "post page renders boost strips for the post and its comments" do
    get admin_post_path(records(:kickoff))
    assert_response :success

    assert_select "turbo-frame#boosts_record_#{records(:kickoff).id}" do
      assert_select ".boost", count: 2
      # Only your own boost carries the circle-x.
      assert_select ".boost .boost__remove", count: 1
      assert_select "form[action=?] button.boost__remove", admin_boost_path(boosts(:alice_kickoff))
      # The chip discloses the bordered field: input + smiley/check/x triggers.
      assert_select "details.boosts__composer summary.boosts__prompt", text: "+ Boost"
      assert_select ".boosts__field input[maxlength=?]", "16"
      assert_select ".boosts__field button[popovertarget=?]", "boost-menu-#{records(:kickoff).id}"
      assert_select ".boosts__field button[type=submit]"
      assert_select ".boosts__field button[type=reset][data-action=?]", "disclosure#close"
      # The palette popover holds only the emoji quick picks, floated above.
      assert_select ".boosts__palette[data-anchored-popover-placement-value=above] .boosts__emoji",
        count: Boost::COMMON_EMOJIS.size
    end

    assert_select "turbo-frame#boosts_record_#{records(:kickoff_comment).id} summary.boosts__prompt"
  end

  test "create adds a boost to a post record" do
    assert_difference -> { records(:kickoff).boosts.count } do
      post admin_record_boosts_path(records(:kickoff)), params: { boost: { content: "💯" } }
    end

    assert_redirected_to admin_post_path(records(:kickoff), anchor: "boosts_record_#{records(:kickoff).id}")
    assert_equal users(:alice), Boost.last.creator
  end

  test "create adds a boost to a comment record and lands back on the post page" do
    record = records(:kickoff_comment)

    assert_difference -> { record.boosts.count } do
      post admin_record_boosts_path(record), params: { boost: { content: "so true" } }
    end

    assert_redirected_to admin_post_path(records(:kickoff), anchor: "boosts_record_#{record.id}")
  end

  test "create on a message record lands back on the message page" do
    record = records(:welcome)

    assert_difference -> { record.boosts.count } do
      post admin_record_boosts_path(record), params: { boost: { content: "🎉" } }
    end

    assert_redirected_to admin_message_path(record, anchor: "boosts_record_#{record.id}")
  end

  test "create on a comment under a message lands back on the message page" do
    record = records(:welcome_comment)

    assert_difference -> { record.boosts.count } do
      post admin_record_boosts_path(record), params: { boost: { content: "hi" } }
    end

    assert_redirected_to admin_message_path(records(:welcome), anchor: "boosts_record_#{record.id}")
  end

  test "create ignores blank content" do
    assert_no_difference -> { Boost.count } do
      post admin_record_boosts_path(records(:kickoff)), params: { boost: { content: "" } }
    end
    assert_response :redirect
  end

  test "create rejects a trashed record" do
    records(:kickoff_comment).trash

    assert_no_difference -> { Boost.count } do
      post admin_record_boosts_path(records(:kickoff_comment)), params: { boost: { content: "🙌" } }
    end
    assert_response :not_found
  end

  test "destroy removes your own boost" do
    assert_difference -> { Boost.count }, -1 do
      delete admin_boost_path(boosts(:alice_kickoff))
    end

    assert_redirected_to admin_post_path(records(:kickoff), anchor: "boosts_record_#{records(:kickoff).id}")
  end

  test "destroy cannot touch someone else's boost" do
    assert_no_difference -> { Boost.count } do
      delete admin_boost_path(boosts(:bob_kickoff))
    end
    assert_response :not_found
  end
end
