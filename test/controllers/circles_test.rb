require "test_helper"

class CirclesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "the circles index lists the circles you're in" do
    sign_in_as users(:bob)

    get circles_path
    assert_response :success
    assert_match "Writers Circle", response.body
    # Same canvas chrome as the board: a "Circles" breadcrumb and perma-header.
    assert_select ".breadcrumb__item--current", text: "Circles"
    assert_select ".perma-header__title", text: "Your circles"
    # The list ⇄ cards toggle, defaulting to list.
    assert_select ".segmented__seg[data-view=list][aria-selected=true]"
    assert_select ".segmented__seg[data-view=cards]"
    assert_select "ul.circles[data-view=list]"
  end

  test "the index puts New circle in the canvas head and links the wider world" do
    Circle.create_with_owner(name: "Poets Circle", owner: users(:admin))
    sign_in_as users(:bob)

    get circles_path
    # New circle rides the canvas head (bob owns none, so he may create).
    assert_select ".canvas__head a[href=?]", new_circle_path
    assert_select ".perma-header__toolbar", count: 0
    # Drafts-style link out to every circle on the platform.
    assert_select "a[href=?]", all_circles_path, text: "View all 2 circles on Inkwell"
  end

  test "all circles lists everything, but only yours are doors" do
    other = Circle.create_with_owner(name: "Poets Circle", owner: users(:admin))
    sign_in_as users(:bob)

    get all_circles_path
    assert_response :success
    assert_select ".circles__name", text: "Writers Circle"
    assert_select ".circles__name", text: "Poets Circle"
    assert_select "a.circles__card[href=?]", circle_path(circles(:writers))
    assert_select "a.circles__card[href=?]", circle_path(other), count: 0
    assert_select ".circles__meta", text: /invite-only/

    # A pending seat follows you here — its circle shows as the golden card.
    other.invitations.create!(user: users(:bob), inviter: users(:admin))
    get all_circles_path
    assert_select ".circles__card--invited .circles__name", text: "Poets Circle"
    assert_select ".circles__meta", text: /invite-only/, count: 0
  end

  test "the circles index honors the persisted layout cookie" do
    sign_in_as users(:bob)
    cookies[:circles_view] = "cards"

    get circles_path
    assert_select "ul.circles[data-view=cards]"
    assert_select ".segmented__seg[data-view=cards][aria-selected=true]"
  end

  test "the circle home is the feed: canvas chrome, a New post action, the kind filter" do
    sign_in_as users(:bob)

    get circle_path(circles(:writers))
    assert_response :success
    # Same canvas chrome as a post: a "Circles / <name>" breadcrumb and the
    # circle name as the perma-header title.
    assert_select ".breadcrumb a", text: "Circles"
    assert_select ".breadcrumb__item--current", text: circles(:writers).name
    assert_select ".perma-header__title", text: circles(:writers).name
    # The feed: a New post head action, the segmented kind filter, and the
    # fixture discussion as a card.
    assert_select ".canvas__head a[href=?][data-turbo-frame=modal]", circle_wall_composer_path(circles(:writers)), text: /New post/
    assert_select "nav.segmented a", text: "Everything"
    assert_select "nav.segmented a", text: "Pulse Checks"
    assert_select "nav.segmented a", text: "Posts", count: 0
    assert_select ".wall__card .wall__title a", text: "Welcome to the circle"
  end

  test "the feed is published-only — no drafts or scheduled cards, even the author's" do
    create_discussion(creator: users(:bob), status: :drafted, title: "Drafty")
    Current.with_bucket(circles(:writers)) do
      message = Message.new(title: "Way out", content: "later", creator: users(:bob), status: :drafted)
      Record.originate(message)
      message.schedule(at: 2.days.from_now, creator: users(:bob))
    end

    sign_in_as users(:bob)
    get circle_path(circles(:writers))
    assert_select ".wall__card .wall__title a", text: "Drafty", count: 0
    assert_select ".wall__card .wall__title a", text: "Way out", count: 0
    assert_select ".wall__card .wall__title a", text: "Welcome to the circle"
  end

  test "the discussions index lists every discussion" do
    sign_in_as users(:bob)

    get circle_messages_path(circles(:writers))
    assert_response :success
    assert_select ".perma-header__title", text: "Discussions"
    assert_select ".list__title", text: "Welcome to the circle"
  end

  test "a discussion has its own page" do
    sign_in_as users(:bob)
    discussion = circles(:writers).messages.first

    get circle_message_path(circles(:writers), discussion.record)
    assert_response :success
    assert_select ".perma-header__title", text: "Welcome to the circle"
    assert_match "introduce yourself", response.body
    # Copy-link is available to any viewer.
    assert_select ".canvas__head button[data-clipboard-text-value*=?]", "/messages/", text: "Copy link"
  end

  test "the new message page renders the rich-text composer with publish controls" do
    sign_in_as users(:bob)

    get new_circle_message_path(circles(:writers))
    assert_response :success
    assert_select ".breadcrumb__item--current", text: "New message"
    # The title is the borderless composer field, not a perma-header.
    assert_select "form#composer input.composer__title[name=?]", "message[title]"
    assert_select "form#composer lexxy-editor"
    # Submit controls live in the canvas head (schedule / draft / post), not a
    # one-off button at the bottom.
    assert_select ".canvas__head button", text: "Post"
    assert_select ".canvas__head button", text: "Save draft"
  end

  test "the membership page holds the roster, the invite form, and pending seats" do
    sign_in_as users(:bob)

    # The circle home: avatars in the header, Membership in the ⋯ menu.
    get circle_path(circles(:writers))
    assert_select ".perma-header .avatar-group"
    assert_select ".menu a[href=?]", circle_members_path(circles(:writers)), text: "Membership"

    get circle_members_path(circles(:writers))
    assert_response :success
    assert_select ".perma-header__title", text: "Who's in this circle?"
    assert_select "form[action=?] input[name=email_address]", circle_invitations_path(circles(:writers))
    assert_select ".list__title", text: users(:alice).display_name
    assert_select ".badge", text: "Owner"
  end

  test "a member leaves a circle from the context menu; the owner cannot" do
    sign_in_as users(:bob) # member, not owner

    get circle_path(circles(:writers))
    assert_select ".menu form[action=?]", circle_membership_path(circles(:writers))

    assert_difference -> { circles(:writers).circle_memberships.count }, -1 do
      delete circle_membership_path(circles(:writers))
    end
    assert_redirected_to circles_path
    assert_not circles(:writers).member?(users(:bob))

    sign_in_as users(:alice) # owner
    get circle_path(circles(:writers))
    assert_select ".menu form[action=?]", circle_membership_path(circles(:writers)), count: 0
    assert_no_difference -> { circles(:writers).circle_memberships.count } do
      delete circle_membership_path(circles(:writers))
    end
    assert_redirected_to circle_path(circles(:writers))
  end

  test "a non-member gets the same 404 as a missing record" do
    sign_in_as users(:admin) # root, but not a member of this circle

    get circle_path(circles(:writers))
    assert_response :not_found
  end

  test "signed-out visitors are bounced to sign-in" do
    get circle_path(circles(:writers))
    assert_redirected_to new_session_path
  end

  test "posting publishes the discussion, owned by the circle" do
    sign_in_as users(:bob)

    assert_difference -> { circles(:writers).messages.count }, 1 do
      post circle_messages_path(circles(:writers)),
        params: { message: { title: "Standup", content: "Wrote 500 words today." }, publish: "1" }
    end

    message = circles(:writers).messages.find { |m| m.title == "Standup" }
    assert_redirected_to circle_message_path(circles(:writers), message.record)
    assert_equal "Circle", message.record.bucket_type
    assert_equal circles(:writers).id, message.record.bucket_id
    assert message.published?
  end

  test "a discussion can be saved as a draft" do
    sign_in_as users(:bob)

    post circle_messages_path(circles(:writers)), params: { message: { title: "WIP", content: "later" } }

    assert circles(:writers).messages.find { |m| m.title == "WIP" }.drafted?
  end

  test "a discussion can be scheduled for later" do
    sign_in_as users(:bob)

    assert_enqueued_with job: Record::PublishLaterJob do
      post circle_messages_path(circles(:writers)), params: {
        message: { title: "Soon", content: "later" },
        scheduled_posting: "true",
        scheduled_posting_at_date: Date.tomorrow.iso8601,
        scheduled_posting_at_hour: "9"
      }
    end

    assert circles(:writers).messages.find { |m| m.title == "Soon" }.scheduled?
  end

  test "a titleless post is rejected and re-renders the composer" do
    sign_in_as users(:bob)

    assert_no_difference -> { circles(:writers).messages.count } do
      post circle_messages_path(circles(:writers)), params: { message: { title: "", content: "hi" }, publish: "1" }
    end
    assert_response :unprocessable_entity
  end

  # ── Draft/scheduled visibility ─────────────────────────────────────────────

  test "a draft is visible to its author and the circle owner, hidden from other members" do
    draft = create_discussion(creator: users(:bob), status: :drafted, title: "Bob's draft")

    sign_in_as users(:bob) # author
    get circle_messages_path(circles(:writers))
    assert_select ".list__title", text: "Bob's draft"

    sign_in_as users(:alice) # circle owner
    get circle_messages_path(circles(:writers))
    assert_select ".list__title", text: "Bob's draft"

    # A third member who is neither author nor owner doesn't see it.
    carol = User.create!(email_address: "carol@example.com", role: :member)
    circles(:writers).circle_memberships.create!(user: carol)
    sign_in_as carol
    get circle_messages_path(circles(:writers))
    assert_select ".list__title", text: "Bob's draft", count: 0
  end

  test "a non-author, non-owner opening a draft directly gets a 404" do
    draft = create_discussion(creator: users(:alice), status: :drafted, title: "Owner draft")
    carol = User.create!(email_address: "carol@example.com", role: :member)
    circles(:writers).circle_memberships.create!(user: carol)

    sign_in_as carol
    get circle_message_path(circles(:writers), draft.record)
    assert_response :success # membership lets them read it via the show route
  end

  test "a scheduled discussion shows only in the scheduled view, not the main list" do
    scheduled = create_discussion(creator: users(:bob), status: :scheduled, title: "Queued up")
    scheduled.update!(published_at: 1.week.from_now)
    sign_in_as users(:bob)

    # Not in the main discussions list…
    get circle_messages_path(circles(:writers))
    assert_select ".list__title", text: "Queued up", count: 0
    assert_select "a[href=?]", circle_messages_path(circles(:writers), scheduled: 1), text: /1 scheduled discussion/

    # …but present in the scheduled view.
    get circle_messages_path(circles(:writers), scheduled: 1)
    assert_select ".list__title", text: "Queued up"
  end

  # ── Manage: edit / archive / trash ─────────────────────────────────────────

  test "the author can edit a discussion" do
    discussion = create_discussion(creator: users(:bob), title: "Editable")
    sign_in_as users(:bob)

    patch circle_message_path(circles(:writers), discussion.record),
      params: { message: { title: "Edited", content: "changed" } }

    assert_redirected_to circle_message_path(circles(:writers), discussion.record)
    assert_equal "Edited", discussion.record.reload.recordable.title
  end

  test "the circle owner can archive and unarchive any discussion" do
    discussion = create_discussion(creator: users(:bob), title: "To archive")
    sign_in_as users(:alice) # owner, not author

    patch archive_circle_message_path(circles(:writers), discussion.record)
    assert discussion.record.reload.archived?
    # Archived discussions drop out of the main list, into the archived view.
    get circle_messages_path(circles(:writers))
    assert_select ".list__title", text: "To archive", count: 0
    get archived_circle_messages_path(circles(:writers))
    assert_select ".list__title", text: "To archive"

    patch unarchive_circle_message_path(circles(:writers), discussion.record)
    assert_not discussion.record.reload.archived?
  end

  test "a member who is neither author nor owner cannot manage a discussion" do
    discussion = create_discussion(creator: users(:alice), title: "Owner's")
    carol = User.create!(email_address: "carol@example.com", role: :member)
    circles(:writers).circle_memberships.create!(user: carol)

    sign_in_as carol
    patch archive_circle_message_path(circles(:writers), discussion.record)
    assert_response :not_found
    assert_not discussion.record.reload.archived?
  end

  test "the author can trash a discussion" do
    discussion = create_discussion(creator: users(:bob), title: "Doomed")
    sign_in_as users(:bob)

    delete circle_message_path(circles(:writers), discussion.record)
    assert_redirected_to circle_messages_path(circles(:writers))
    assert discussion.record.reload.trashed?
  end

  # ── Circle editing ─────────────────────────────────────────────────────────

  test "the owner can edit the circle's name, description, and charter" do
    sign_in_as users(:alice)

    patch circle_path(circles(:writers)), params: { circle: { name: "Renamed",
      description: "A cozy group.", charter: "Useful comment before a kind one\nA run can be shelved" } }

    assert_redirected_to circle_path(circles(:writers))
    circles(:writers).reload
    assert_equal "Renamed", circles(:writers).name
    assert_equal "A cozy group.", circles(:writers).description
    # The charter parses into the sidebar's "decided here" lines.
    assert_equal ["Useful comment before a kind one", "A run can be shelved"], circles(:writers).decisions
  end

  test "the board rail carries the charter's decisions and who has posted lately" do
    circle = circles(:writers)
    circle.update!(charter: "Useful comment before a kind one\nA run can be shelved, not paused")
    create_discussion(title: "Recent one", creator: users(:bob))

    sign_in_as users(:bob)
    get circle_path(circle)
    # The rail is the board's right-hand column, not a popover.
    assert_select ".circle-board > .circle-rail#circle-rail"
    # Decided here: the owner's charter lines, one per item.
    assert_select "#circle-rail .circle-rail__item", text: "Useful comment before a kind one"
    assert_select "#circle-rail .circle-rail__item", text: "A run can be shelved, not paused"
    # Who's talking: bob posted, so he rides the chips; the caption counts posters.
    assert_select "#circle-rail .circle-rail__chips .avatar"
    assert_select "#circle-rail .circle-rail__caption", text: /of \d+ posted to the board in the last 30 days/
  end

  test "a non-owner member cannot edit the circle" do
    sign_in_as users(:bob) # member, not owner

    get edit_circle_path(circles(:writers))
    assert_response :not_found
  end

  # ── Creating circles ───────────────────────────────────────────────────────

  test "a member can create one circle and becomes its owner" do
    carol = User.create!(email_address: "carol@example.com", role: :member)
    sign_in_as carol

    assert_difference -> { Circle.count }, 1 do
      post circles_path, params: { circle: { name: "Carol's Circle", description: "Ours." } }
    end
    circle = Circle.find_by(name: "Carol's Circle")
    assert_redirected_to circle_path(circle)
    assert_equal carol, circle.owner
    assert circle.member?(carol)
  end

  test "a member is capped at one circle; an admin is not" do
    carol = User.create!(email_address: "carol@example.com", role: :member)
    Circle.create_with_owner(name: "First", owner: carol)
    sign_in_as carol

    # Second circle is blocked, and the New-circle affordance is gone.
    get circles_path
    assert_select "a[href=?]", new_circle_path, count: 0
    assert_no_difference -> { Circle.count } do
      post circles_path, params: { circle: { name: "Second" } }
    end
    assert_redirected_to circles_path

    # Admins (root) are uncapped.
    Circle.create_with_owner(name: "Admin one", owner: users(:admin))
    sign_in_as users(:admin)
    assert_difference -> { Circle.count }, 1 do
      post circles_path, params: { circle: { name: "Admin two" } }
    end
  end

  # ── Comments on discussions ────────────────────────────────────────────────

  test "a member comments on a discussion and it shows chronologically" do
    discussion = create_discussion(creator: users(:alice), title: "Talk")
    sign_in_as users(:bob)

    assert_difference -> { discussion.record.comments.count }, 1 do
      post circle_record_comments_path(circles(:writers), discussion.record),
        params: { comment: { content: "<p>First reply</p>" } }
    end

    get circle_message_path(circles(:writers), discussion.record)
    assert_response :success
    assert_select "#comments .comment__body", text: /First reply/
    # The comment lives in the circle, not an account.
    assert_equal "Circle", discussion.record.comments.first.record.bucket_type

    # The discussions list carries the activity line: count, the commenters'
    # faces, and how long since the last word.
    get circle_messages_path(circles(:writers))
    assert_select ".list__item .list__activity", text: /1 comment.*ago/m
    assert_select ".list__activity .avatar-group"
  end

  test "only the comment's author can edit it" do
    discussion = create_discussion(creator: users(:alice), title: "Talk")
    comment = comment_on(discussion, author: users(:bob), body: "mine")

    sign_in_as users(:bob) # author
    get edit_circle_comment_path(circles(:writers), comment.record)
    assert_response :success

    sign_in_as users(:alice) # circle owner, but not the author — no edit
    get edit_circle_comment_path(circles(:writers), comment.record)
    assert_response :not_found
  end

  test "the circle owner can trash any comment (moderation override), a stranger cannot" do
    discussion = create_discussion(creator: users(:alice), title: "Talk")
    comment = comment_on(discussion, author: users(:bob), body: "moderate me")

    # A third member who isn't the author or owner can't trash it.
    carol = User.create!(email_address: "carol@example.com", role: :member)
    circles(:writers).circle_memberships.create!(user: carol)
    sign_in_as carol
    delete circle_comment_path(circles(:writers), comment.record)
    assert_response :not_found
    assert_not comment.record.reload.trashed?

    # The circle owner (not the author) may — the override.
    sign_in_as users(:alice)
    delete circle_comment_path(circles(:writers), comment.record)
    assert comment.record.reload.trashed?
  end

  private
    def comment_on(discussion, author:, body:)
      Current.with_bucket(circles(:writers)) do
        comment = Comment.new(content: body, creator: author)
        Record.originate(comment, parent: discussion.record)
        comment
      end
    end

    def create_discussion(creator:, title:, status: :published)
      circle = circles(:writers)
      Current.with_bucket(circle) do
        message = Message.new(title: title, content: "body", creator: creator, status: status,
          published_at: (Time.current if status == :published))
        Record.originate(message)
        message
      end
    end
end
