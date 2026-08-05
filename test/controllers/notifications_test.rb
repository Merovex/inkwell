require "test_helper"

# The bell: notifications are born only through Notification.deliver, die with
# their sources, email per their kind's class, and clear on one read_all.
class NotificationsTest < ActionDispatch::IntegrationTest
  setup { @circle = circles(:writers) }

  test "an invitation notifies the invitee — bell row plus immediate email" do
    sign_in_as users(:bob)

    assert_difference -> { users(:admin).notifications.count }, 1 do
      assert_enqueued_jobs 1, only: ApplicationMailDeliveryJob do
        post circle_invitations_path(@circle), params: { email_address: users(:admin).email_address }
      end
    end
    notification = users(:admin).notifications.last
    assert_equal "invited", notification.kind

    # The invitee's bell: lit dot, and the row reads as a sentence with a door.
    sign_in_as users(:admin)
    get circles_path
    assert_select ".notifications__dot--on"
    assert_select ".notifications__row", text: /benwilson.* invited you to #{@circle.name}|invited you to/
  end

  test "revoking an invitation takes the notification with it" do
    sign_in_as users(:bob)
    post circle_invitations_path(@circle), params: { email_address: users(:admin).email_address }
    invitation = @circle.invitations.last

    assert_difference -> { users(:admin).notifications.count }, -1 do
      delete circle_invitation_path(@circle, invitation)
    end
  end

  test "accepting notifies the inviter (bell-only) and retires the invited row" do
    sign_in_as users(:bob)
    post circle_invitations_path(@circle), params: { email_address: users(:admin).email_address }
    invitation = @circle.invitations.last

    sign_in_as users(:admin)
    assert_no_enqueued_jobs only: ApplicationMailDeliveryJob do
      post accept_circle_invitation_path(@circle, invitation)
    end
    # The announcement OUTLIVES the accepted invitation — its copy is stamped.
    invited = users(:admin).notifications.last
    assert_equal "invited", invited.kind
    assert_nil invited.source_type
    assert_match(/invited you to #{@circle.name}/, invited.title)
    accepted = users(:bob).notifications.last
    assert_equal "invitation_accepted", accepted.kind
    assert_equal "CircleMembership", accepted.source_type

    # And the bell still lists it after the accept.
    get circles_path
    assert_select ".notifications__row", text: /invited you to #{@circle.name}/
  end

  test "opening the bell marks everything read" do
    Notification.deliver(@circle.invitations.create!(user: users(:admin), inviter: users(:alice)),
      to: users(:admin), kind: "invited")
    sign_in_as users(:admin)

    post read_all_notifications_path
    assert_response :no_content
    assert_equal 0, users(:admin).notifications.unread.count
  end

  test "the full page lists the 30-day window and counts as the deepest read" do
    invitation = @circle.invitations.create!(user: users(:admin), inviter: users(:alice))
    Notification.deliver(invitation, to: users(:admin), kind: "invited")
    sign_in_as users(:admin)

    get circles_path
    assert_select ".notifications__all", text: "See all notifications"

    get notifications_path
    assert_response :success
    assert_select ".list__title", text: /invited you to #{@circle.name}/
    assert_equal 0, users(:admin).notifications.unread.count
  end

  test "read notifications are pruned after thirty days; unread wait" do
    invitation = @circle.invitations.create!(user: users(:admin), inviter: users(:alice))
    read   = Notification.deliver(invitation, to: users(:admin), kind: "invited")
    unread = Notification.deliver(invitation, to: users(:bob), kind: "invited")
    read.update!(read_at: 31.days.ago)

    assert_difference -> { Notification.count }, -1 do
      NotificationPruneJob.perform_now
    end
    assert Notification.exists?(unread.id)
  end
end
