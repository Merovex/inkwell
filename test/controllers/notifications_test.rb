require "test_helper"

# The bell: notifications are born only through Notification.deliver, die with
# their sources, email per their kind's class, and clear on one reading.
class NotificationsTest < ActionDispatch::IntegrationTest
  setup { @circle = circles(:writers) }

  test "an invitation notifies the invitee — bell row now, email by digest" do
    sign_in_as users(:bob)

    assert_difference -> { users(:admin).notifications.count }, 1 do
      assert_no_enqueued_jobs only: ApplicationMailDeliveryJob do
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
      post circle_invitation_acceptance_path(@circle, invitation)
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

    post notifications_reading_path
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

  test "the digest rolls up unread email-worthy notifications, once" do
    invitation = @circle.invitations.create!(user: users(:admin), inviter: users(:alice))
    Notification.deliver(invitation, to: users(:admin), kind: "invited")

    # One email for the batch; the batch is stamped as covered.
    assert_enqueued_jobs 1, only: ApplicationMailDeliveryJob do
      NotificationDigestJob.perform_now
    end
    assert users(:admin).notifications.last.emailed_at?

    # A second run finds nothing new.
    assert_no_enqueued_jobs only: ApplicationMailDeliveryJob do
      NotificationDigestJob.perform_now
    end
  end

  test "reading in-app before the digest cancels the email" do
    invitation = @circle.invitations.create!(user: users(:admin), inviter: users(:alice))
    notification = Notification.deliver(invitation, to: users(:admin), kind: "invited")
    notification.update!(read_at: Time.current)

    assert_no_enqueued_jobs only: ApplicationMailDeliveryJob do
      NotificationDigestJob.perform_now
    end
    assert notification.reload.emailed_at? # covered, so the scope stays small
  end

  test "an @mention in a comment notifies the member, and only members" do
    users(:alice).update!(name: "alice") # handle-shaped, like generated names
    discussion = Current.with_bucket(@circle) do
      Record.originate(Message.new(title: "Hello", content: "start", creator: users(:alice),
        status: :published, published_at: Time.current))
    end
    sign_in_as users(:bob)

    assert_difference -> { users(:alice).notifications.count }, 1 do
      post circle_record_comments_path(@circle, discussion),
        params: { comment: { content: "<p>Good point @alice — and @nobodyhere too</p>" } }
    end
    notification = users(:alice).notifications.last
    assert_equal "mentioned", notification.kind
    assert_match(/mentioned you in a comment on “Hello”/, notification.title)
    assert_includes Notification::EMAILED, "mentioned" # digest-worthy
  end

  test "a mention by email address reaches the member too" do
    discussion = Current.with_bucket(@circle) do
      Record.originate(Message.new(title: "Hi", content: "start", creator: users(:bob),
        status: :published, published_at: Time.current))
    end
    sign_in_as users(:bob)

    # alice's name ("Alice Example") isn't handle-shaped — email still works.
    assert_difference -> { users(:alice).notifications.count }, 1 do
      post circle_record_comments_path(@circle, discussion),
        params: { comment: { content: "<p>ping @#{users(:alice).email_address}</p>" } }
    end
    assert_equal "mentioned", users(:alice).notifications.last.kind
  end

  test "a mention picked from the prompt (attachment by sgid) notifies too" do
    discussion = Current.with_bucket(@circle) do
      Record.originate(Message.new(title: "Hey", content: "start", creator: users(:bob),
        status: :published, published_at: Time.current))
    end
    sign_in_as users(:bob)

    # What Lexxy submits after picking from the @-prompt: an attachment
    # carrying the member's sgid, no plain @token anywhere.
    chip = %(<action-text-attachment sgid="#{users(:alice).attachable_sgid}" content-type="application/vnd.actiontext.mention"></action-text-attachment>)
    assert_difference -> { users(:alice).notifications.count }, 1 do
      post circle_record_comments_path(@circle, discussion),
        params: { comment: { content: "<p>ping #{chip} about this</p>" } }
    end
    assert_equal "mentioned", users(:alice).notifications.last.kind
  end

  test "a comment rings the thread: author and prior commenters, not the commenter" do
    users(:alice).update!(name: "alice")
    discussion = Current.with_bucket(@circle) do
      Record.originate(Message.new(title: "Thread", content: "start", creator: users(:alice),
        status: :published, published_at: Time.current))
    end
    # admin joins the thread first, so bob's comment should ring alice AND admin
    @circle.circle_memberships.create!(user: users(:admin))
    Current.with_bucket(@circle) do
      Record.originate(Comment.new(content: "first!", creator: users(:admin)), parent: discussion)
    end
    sign_in_as users(:bob)

    assert_difference -> { users(:alice).notifications.count } => 1,
                      -> { users(:admin).notifications.count } => 1,
                      -> { users(:bob).notifications.count } => 0 do
      post circle_record_comments_path(@circle, discussion),
        params: { comment: { content: "<p>me too</p>" } }
    end
    notification = users(:alice).notifications.last
    assert_equal "replied", notification.kind
    assert_match(/commented on “Thread”/, notification.title)
    assert_includes Notification::EMAILED, "replied"
  end

  test "a mention in the comment wins over the reply ring — one row, not two" do
    users(:alice).update!(name: "alice")
    discussion = Current.with_bucket(@circle) do
      Record.originate(Message.new(title: "Once", content: "start", creator: users(:alice),
        status: :published, published_at: Time.current))
    end
    sign_in_as users(:bob)

    assert_difference -> { users(:alice).notifications.count }, 1 do
      post circle_record_comments_path(@circle, discussion),
        params: { comment: { content: "<p>hey @alice</p>" } }
    end
    assert_equal "mentioned", users(:alice).notifications.last.kind
  end

  test "replies wait for the daily digest; the 4-hour one skips them" do
    users(:alice).update!(name: "alice")
    discussion = Current.with_bucket(@circle) do
      Record.originate(Message.new(title: "Cadence", content: "start", creator: users(:alice),
        status: :published, published_at: Time.current))
    end
    comment = Current.with_bucket(@circle) do
      Record.originate(Comment.new(content: "ping", creator: users(:bob)), parent: discussion)
    end
    Replies.deliver_for(comment)
    replied = users(:alice).notifications.where(kind: "replied").last

    assert_no_enqueued_jobs only: ApplicationMailDeliveryJob do
      NotificationDigestJob.perform_now # 4-hour cadence: replied excluded
    end
    assert_nil replied.reload.emailed_at

    assert_enqueued_jobs 1, only: ApplicationMailDeliveryJob do
      NotificationDigestJob.perform_now(Notification::EMAILED_DAILY)
    end
    assert replied.reload.emailed_at?
  end

  test "mentions in a draft stay quiet; publishing is what rings" do
    users(:alice).update!(name: "alice")
    sign_in_as users(:bob)

    assert_no_difference -> { users(:alice).notifications.count } do
      post circle_messages_path(@circle), params: { message: { title: "WIP", content: "hey @alice" } }
    end
    assert_difference -> { users(:alice).notifications.count }, 1 do
      post circle_messages_path(@circle),
        params: { message: { title: "Live", content: "hey @alice" }, publish: "1" }
    end
  end

  test "publishing a drafted message is what rings its mentions" do
    users(:alice).update!(name: "alice")
    sign_in_as users(:bob)
    post circle_messages_path(@circle), params: { message: { title: "Later", content: "hey @alice" } }
    draft = @circle.discussions_visible_to(users(:bob)).find { |m| m.title == "Later" }

    assert_difference -> { users(:alice).notifications.count }, 1 do
      patch circle_message_path(@circle, draft.record),
        params: { message: { title: "Later", content: "hey @alice" }, publish: "1" }
    end
    assert_equal "mentioned", users(:alice).notifications.last.kind
  end

  test "the pulse ask rings the bell alongside its email" do
    pulse = Current.with_bucket(@circle) do
      Record.originate(Pulse.new(question: "How goes it?", creator: users(:alice),
        cadence: "daily", days_of_week: 0b1111111, ask_at_minutes: 540))
    end.recordable
    pulse.subscriptions.create!(user: users(:bob))

    assert_difference -> { users(:bob).notifications.count }, 1 do
      assert_enqueued_jobs 1, only: ApplicationMailDeliveryJob do
        pulse.ask!
      end
    end
    notification = users(:bob).notifications.last
    assert_equal "pulse_asked", notification.kind
    assert_match(/How goes it\?/, notification.title)
    assert_nil notification.actor # the schedule fired, not a person
    assert_not_includes Notification::EMAILED, "pulse_asked" # PulseMailer is its email
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
