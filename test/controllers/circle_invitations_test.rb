require "test_helper"

class CircleInvitationsTest < ActionDispatch::IntegrationTest
  setup do
    @circle = circles(:writers)
  end

  test "a member invites another user by email" do
    sign_in_as users(:bob) # plain member, not the owner

    assert_difference -> { @circle.invitations.count } => 1 do
      post circle_invitations_path(@circle), params: { email_address: "Admin@Example.com" }
    end

    invitation = @circle.invitations.last
    assert_equal users(:admin), invitation.user
    assert_equal users(:bob), invitation.inviter
    assert_redirected_to circle_members_path(@circle)
  end

  test "a non-member cannot invite" do
    sign_in_as users(:admin)

    assert_no_difference -> { CircleInvitation.count } do
      post circle_invitations_path(@circle), params: { email_address: users(:admin).email_address }
    end
    assert_response :not_found
  end

  test "inviting an unknown address or an existing member goes nowhere" do
    sign_in_as users(:alice)

    assert_no_difference -> { CircleInvitation.count } do
      post circle_invitations_path(@circle), params: { email_address: "nobody@example.com" }
      assert_redirected_to circle_members_path(@circle)
      assert_match(/join Inkwell first/, flash[:alert])

      post circle_invitations_path(@circle), params: { email_address: users(:bob).email_address }
      assert_match(/already a member/, flash[:alert])
    end
  end

  test "the invitee sees the offer on their circles index and can accept" do
    invitation = @circle.invitations.create!(user: users(:admin), inviter: users(:alice))
    sign_in_as users(:admin)

    get circles_path
    # The seat on offer leads the deck as a golden card with its own actions.
    assert_select ".circles__card--invited .circles__name", text: @circle.name
    assert_select ".circles__card--invited .circles__meta", text: /invited you/
    assert_select ".circles__card--invited form[action=?]", circle_invitation_acceptance_path(@circle, invitation)

    assert_difference -> { @circle.circle_memberships.count } => 1, -> { CircleInvitation.count } => -1 do
      post circle_invitation_acceptance_path(@circle, invitation)
    end
    assert_redirected_to circle_path(@circle)
    assert @circle.reload.member?(users(:admin))
  end

  test "accepting a seat in a circle that has since filled bounces politely" do
    invitation = @circle.invitations.create!(user: users(:admin), inviter: users(:alice))
    @circle.update!(member_limit: @circle.circle_memberships.count) # now full
    sign_in_as users(:admin)

    assert_no_difference -> { @circle.circle_memberships.count } do
      post circle_invitation_acceptance_path(@circle, invitation)
    end
    assert_redirected_to circles_path
    assert_match(/full/, flash[:alert])
    assert CircleInvitation.exists?(invitation.id)
  end

  test "the invitee can decline; the inviter or owner can revoke; strangers 404" do
    invitation = @circle.invitations.create!(user: users(:admin), inviter: users(:bob))

    # A stranger to the invitation (member, but neither party nor owner) — none here,
    # so prove the invitee path first.
    sign_in_as users(:admin)
    assert_difference -> { CircleInvitation.count } => -1 do
      delete circle_invitation_path(@circle, invitation)
    end
    assert_redirected_to circles_path

    # Owner revokes one extended by someone else.
    invitation = @circle.invitations.create!(user: users(:admin), inviter: users(:bob))
    sign_in_as users(:alice)
    assert_difference -> { CircleInvitation.count } => -1 do
      delete circle_invitation_path(@circle, invitation)
    end
    assert_redirected_to circle_members_path(@circle)
  end

  test "only one standing invitation per person per circle" do
    @circle.invitations.create!(user: users(:admin), inviter: users(:alice))
    sign_in_as users(:bob)

    assert_no_difference -> { CircleInvitation.count } do
      post circle_invitations_path(@circle), params: { email_address: users(:admin).email_address }
    end
    assert_match(/already has an invitation/, flash[:alert])
  end

  test "the membership page carries the invite form and pending seats" do
    @circle.invitations.create!(user: users(:admin), inviter: users(:alice))
    sign_in_as users(:alice)

    get circle_members_path(@circle)
    assert_select ".circle-members__invite input[type=email]"
    assert_select ".badge", text: "Invited"
    # The owner can revoke a pending invitation.
    assert_select ".list__action [title=Revoke]"

    # The circle home keeps the header avatar cluster (the lock icon retired —
    # privacy is the invariant, not a badge).
    get circle_path(@circle)
    assert_select ".perma-header .avatar-group"
  end
end
