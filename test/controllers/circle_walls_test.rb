require "test_helper"
require "turbo/broadcastable/test_helper"

class CircleWallsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  test "a member sees the wall: cards newest-first, click-through titles" do
    create_discussion(title: "First post")
    create_discussion(title: "Second post")
    sign_in_as users(:bob)

    get circle_path(circles(:writers))
    assert_response :success
    assert_select ".wall__card", 3 # the two above + the fixture discussion
    # Newest first.
    assert_select ".wall__card:first-of-type .wall__title a", text: "Second post"
    # Titles open the thread modal, same as the comment links.
    assert_select ".wall__title a[href*=?][data-turbo-frame=modal]", "/threads/"
  end

  test "the wall paginates with a lazy frame cursor" do
    12.times { |i| create_discussion(title: "Post #{i}") }
    sign_in_as users(:bob)

    get circle_path(circles(:writers))
    assert_select ".wall__card", 10
    assert_select "turbo-frame[loading=lazy][src*=?]", "before_id"

    # The cursor page carries the rest (2 created + the fixture discussion),
    # no further frame.
    cursor = css_select("turbo-frame[loading=lazy]").first["src"][/before_id=(\d+)/, 1]
    get circle_path(circles(:writers), before_id: cursor)
    assert_response :success
    assert_select ".wall__card", 3
    assert_select "turbo-frame[loading=lazy]", 0
  end

  test "the Commons wall affixes published bulletins; other walls don't" do
    Circle.provision_commons(owner: users(:alice))
    bulletin = Bulletin.new(title: "Sidebar changes", content: "<p>Soon.</p>",
      creator: users(:alice), event: :created)
    Record.originate(bulletin)
    bulletin.publish(creator: users(:alice))
    sign_in_as users(:bob)

    get circle_path(Circle.commons)
    assert_response :success
    assert_select ".wall__pin--announce", text: /Sidebar changes/

    get circle_path(circles(:writers))
    assert_select ".wall__pin--announce", 0
  end

  test "the wall streams only published messages; your scheduled ride the top strip" do
    create_discussion(title: "Live one")
    scheduled = Current.with_bucket(circles(:writers)) do
      message = Message.new(title: "Way out there", content: "<p>later</p>",
        creator: users(:bob), status: :drafted)
      Record.originate(message)
      message.schedule(at: 2.days.from_now, creator: users(:bob))
      message
    end

    sign_in_as users(:bob)
    get circle_path(circles(:writers))
    # Not in the stream…
    assert_select ".wall__card .wall__title a", text: "Way out there", count: 0
    # …but in bob's own quiet housekeeping line, with its appointment.
    assert_select ".wall__yours", text: /Way out there/
    assert_select ".wall__yours time", 1

    # Alice doesn't see bob's appointments.
    sign_in_as users(:alice)
    get circle_path(circles(:writers))
    assert_select ".wall__yours", 0
    assert scheduled.record.reload.recordable.scheduled?
  end

  test "an unanswered pulse ask pins to the top; answering dissolves it" do
    pulse = Current.with_bucket(circles(:writers)) do
      Record.originate(Pulse.new(question: "What did you work on?", creator: users(:alice),
        cadence: "weekly", days_of_week: (1 << 1), ask_at_minutes: 540))
    end.recordable
    pulse.subscribe(circles(:writers).members) # the controller does this at setup
    pulse.ask!

    sign_in_as users(:bob)
    get circle_path(circles(:writers))
    assert_select ".wall__pin--pulse", text: /Pulse check: What did you work on\?/
    assert_select "a[href=?]", circle_pulse_path(circles(:writers), pulse.record_id), text: /Pulse check/

    Current.with_bucket(circles(:writers)) do
      Record.originate(Beat.new(content: "<p>Wrote plenty</p>", asked_on: pulse.last_asked_on,
        creator: users(:bob)), parent: pulse.record)
    end
    get circle_path(circles(:writers))
    assert_select ".wall__pin--pulse", count: 0

    # The answer rides the wall as its own card — newest, so first — wearing
    # the QUESTION as its title and deep-linking its ask-day.
    day_link = circle_pulse_path(circles(:writers), pulse.record_id, day: pulse.last_asked_on.iso8601)
    assert_select ".wall__card:first-of-type .wall__title a[href=?]", day_link,
      text: /What did you work on\?/
    assert_select ".wall__card:first-of-type .wall__body", text: /Wrote plenty/

    # A second answer is its own card — Beats and Messages, reverse chrono.
    Current.with_bucket(circles(:writers)) do
      Record.originate(Beat.new(content: "<p>Me too</p>", asked_on: pulse.last_asked_on,
        creator: users(:alice)), parent: pulse.record)
    end
    get circle_path(circles(:writers))
    assert_select ".wall__title a", text: /What did you work on\?/, count: 2
    assert_select ".wall__card:first-of-type .wall__body", text: /Me too/

    # The pulse page's ?day= deep link still works; a past day offers no composer.
    day_path = circle_pulse_path(circles(:writers), pulse.record_id, day: pulse.last_asked_on.iso8601)
    get day_path
    assert_response :success
    assert_select "#beats .list__item", 2
    travel 3.days do
      get day_path
      # That week's answers still render, read-only — no composer for a past week.
      assert_select "#beats .list__item", 2
      assert_select "form[action=?]", circle_pulse_beats_path(circles(:writers), pulse.record_id), count: 0
    end
  end

  test "every card carries the menu; Edit/trash items follow capability" do
    message = create_discussion(title: "Mine", creator: users(:bob))

    sign_in_as users(:bob) # the author — Copy link + Edit + trash
    get circle_path(circles(:writers))
    assert_select ".wall__card:first-of-type .wall__actions button", text: "Copy link"
    assert_select ".wall__card:first-of-type .wall__actions a.menu__item[href=?][data-turbo-frame=modal]",
      circle_wall_edit_path(circles(:writers), message.record), text: "Edit"
    assert_select ".wall__card:first-of-type .wall__actions form[action=?]",
      circle_message_path(circles(:writers), message.record)

    sign_in_as users(:alice) # circle owner, not the author — moderate only (no Edit)
    get circle_path(circles(:writers))
    assert_select ".wall__card:first-of-type .wall__actions a.menu__item", text: "Edit", count: 0
    assert_select ".wall__card:first-of-type .wall__actions form[action=?]",
      circle_message_path(circles(:writers), message.record)

    carol = User.create!(email_address: "carol@example.com")
    circles(:writers).circle_memberships.create!(user: carol)
    sign_in_as carol # plain member — the kebab is still there (Copy link), but no Edit/trash
    get circle_path(circles(:writers))
    assert_select ".wall__card:first-of-type .wall__actions button", text: "Copy link"
    assert_select ".wall__card:first-of-type .wall__actions a.menu__item", text: "Edit", count: 0
    assert_select ".wall__card:first-of-type .wall__actions form[action=?]",
      circle_message_path(circles(:writers), message.record), count: 0
  end

  test "trashing a discussion from the feed removes the card in place, no redirect" do
    message = create_discussion(title: "Delete me", creator: users(:bob))
    sign_in_as users(:bob)

    delete circle_message_path(circles(:writers), message.record),
      params: { back: "wall" }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=remove][target=?]",
      ActionView::RecordIdentifier.dom_id(message.record)
    assert message.record.reload.trashed_at.present?
  end

  test "New post opens the compose modal; posting with back=wall lands on the feed" do
    sign_in_as users(:bob)

    # The head action opens the modal, not a full page.
    get circle_path(circles(:writers))
    assert_select ".canvas__head a.canvas__head-action[href=?][data-turbo-frame=modal]",
      circle_wall_composer_path(circles(:writers)), text: "New post"

    # The modal renders the compose form + the full action ladder.
    get circle_wall_composer_path(circles(:writers))
    assert_response :success
    assert_select "turbo-frame#modal dialog form[action=?]", circle_messages_path(circles(:writers))
    assert_select "turbo-frame#modal button", text: "Save draft"
    assert_select "turbo-frame#modal button", text: "Post"

    # Post (publish=1) → published, and lands on the feed.
    post circle_messages_path(circles(:writers)),
      params: { back: "wall", publish: "1", message: { title: "From the modal", content: "<p>hi</p>" } }
    assert_redirected_to circle_path(circles(:writers))
    assert circles(:writers).messages.find { |m| m.title == "From the modal" }.published?

    # Save draft (no publish) → a draft, still back to the feed.
    post circle_messages_path(circles(:writers)),
      params: { back: "wall", message: { title: "A modal draft", content: "<p>later</p>" } }
    assert_redirected_to circle_path(circles(:writers))
    assert circles(:writers).messages.find { |m| m.title == "A modal draft" }.drafted?
  end

  test "the edit modal serves the author, saves back to the wall, and 404s others" do
    message = create_discussion(title: "Mine", creator: users(:bob))

    sign_in_as users(:bob)
    get circle_wall_edit_path(circles(:writers), message.record)
    assert_response :success
    assert_select "turbo-frame#modal dialog form[action=?]",
      circle_message_path(circles(:writers), message.record)

    patch circle_message_path(circles(:writers), message.record),
      params: { back: "wall", message: { title: "Mine, revised", content: "<p>better</p>" } }
    assert_redirected_to circle_path(circles(:writers))
    assert_equal "Mine, revised", message.record.reload.recordable.title

    sign_in_as users(:alice) # owner may moderate, not edit
    get circle_wall_edit_path(circles(:writers), message.record)
    assert_response :not_found
  end

  test "the segmented control links Everything, Pulse Checks, and Progress as their own pages" do
    create_discussion(title: "A post")
    pulse = Current.with_bucket(circles(:writers)) do
      Record.originate(Pulse.new(question: "What did you work on?", creator: users(:alice),
        cadence: "weekly", days_of_week: (1 << 1), ask_at_minutes: 540))
    end.recordable
    Current.with_bucket(circles(:writers)) do
      Record.originate(Beat.new(content: "<p>Wrote plenty</p>", asked_on: Date.current,
        creator: users(:bob)), parent: pulse.record)
    end
    sign_in_as users(:bob)

    # Everything: the message card and the beat card (titled by its question),
    # plus the segments linking to their sibling pages. No "Posts" segment.
    get circle_path(circles(:writers))
    assert_select "nav.segmented a[aria-current=page]", text: "Everything"
    assert_select "nav.segmented a", text: "Posts", count: 0
    assert_select "nav.segmented a[href=?]", circle_checks_path(circles(:writers)), text: "Pulse Checks"
    assert_select "nav.segmented a[href=?]", circle_progress_path(circles(:writers)), text: "Progress"
    assert_select ".wall__title a", text: "A post"
    assert_select ".wall__title a", text: /What did you work on\?/

    # Pulse Checks is its own page: the check listed as a door to its pulse (so
    # you can reach it even with no answers), not a filtered feed of beats.
    get circle_checks_path(circles(:writers))
    assert_response :success
    assert_select "nav.segmented a[aria-current=page]", text: "Pulse Checks"
    # The primary check is shown in full detail here, not a feed of beats.
    assert_select ".check-detail__title", text: /What did you work on\?/
    assert_select ".wall__title a", text: "A post", count: 0
  end

  test "your drafts count links to the Discussions list; none, no line" do
    Current.with_bucket(circles(:writers)) do
      draft = Message.new(title: "Half-formed", content: "<p>hm</p>",
        creator: users(:bob), status: :drafted)
      Record.originate(draft)
    end

    sign_in_as users(:bob)
    get circle_path(circles(:writers))
    assert_select "a[href=?]", circle_messages_path(circles(:writers)), text: "You have 1 draft"
    # Not in the stream either.
    assert_select ".wall__card .wall__title a", text: "Half-formed", count: 0

    sign_in_as users(:alice)
    get circle_path(circles(:writers))
    assert_select "a", text: /You have \d+ draft/, count: 0
  end

  test "a non-member gets the same 404 as a missing circle" do
    outsider = User.create!(email_address: "outsider@example.com")
    sign_in_as outsider
    get circle_path(circles(:writers))
    assert_response :not_found
  end

  test "a card carries its commenters as an avatar cluster beside the count" do
    discussion = create_discussion(title: "Talk to me", creator: users(:alice))
    sign_in_as users(:bob)
    post circle_record_comments_path(circles(:writers), discussion.record),
      params: { comment: { content: "<p>A reply</p>" } }

    get circle_path(circles(:writers))
    assert_response :success
    assert_select ".wall__card .wall__footer .avatar-group .avatar"
    assert_select ".wall__card .wall__footer", text: /1 comment/
  end

  test "cards clamp the body and open the thread as a modal" do
    message = create_discussion(title: "Long one")
    sign_in_as users(:bob)

    get circle_path(circles(:writers))
    assert_select ".wall__body.u-clamp"
    assert_select "a[href=?][data-turbo-frame=modal]",
      circle_wall_thread_path(circles(:writers), message.record)
  end

  test "a beat has a comment thread: count on the card, modal with composer" do
    pulse = Current.with_bucket(circles(:writers)) do
      Record.originate(Pulse.new(question: "How goes it?", creator: users(:alice),
        cadence: "weekly", days_of_week: (1 << 1), ask_at_minutes: 540))
    end.recordable
    beat = Current.with_bucket(circles(:writers)) do
      Record.originate(Beat.new(content: "<p>Well enough</p>", asked_on: Date.current,
        creator: users(:bob)), parent: pulse.record)
    end.recordable

    sign_in_as users(:alice)
    get circle_path(circles(:writers))
    # No comments yet — the affordance is the "Comment" action, not "0 comments".
    assert_select ".wall__card:first-of-type a[href=?]",
      circle_wall_thread_path(circles(:writers), beat.record_id), text: /Comment/

    get circle_wall_thread_path(circles(:writers), beat.record_id)
    assert_response :success
    assert_select ".modal__title", text: "How goes it?"
    assert_select ".modal__body .prose", text: /Well enough/
    assert_select ".wall-thread__composer form[action=?]",
      circle_record_comments_path(circles(:writers), beat.record_id)

    post circle_record_comments_path(circles(:writers), beat.record_id),
      params: { back: "wall", comment: { content: "<p>Glad to hear</p>" } }
    follow_redirect!
    assert_select ".comments .list__item", minimum: 1
  end

  test "the thread modal carries the message, boosts, comments, and the composer" do
    message = create_discussion(title: "Discuss me")
    sign_in_as users(:bob)

    get circle_wall_thread_path(circles(:writers), message.record)
    assert_response :success
    assert_select "turbo-frame#modal dialog.wall-thread"
    assert_select ".modal__title", text: "Discuss me"
    assert_select ".boosts form[action=?]", circle_record_boosts_path(circles(:writers), message.record)
    assert_select ".wall-thread__composer form[action=?]",
      circle_record_comments_path(circles(:writers), message.record)
  end

  test "a comment broadcasts the card's live count; forum comments stay quiet" do
    message = create_discussion(title: "Counted live")
    sign_in_as users(:bob)

    assert_turbo_stream_broadcasts([ circles(:writers), :wall ], count: 1) do
      perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
        post circle_record_comments_path(circles(:writers), message.record),
          params: { comment: { content: "<p>count me</p>" } }
      end
    end

    # A forum (account-bucket) comment reaches no wall stream.
    assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
      comment = Comment.new(content: "<p>forum</p>", creator: users(:bob))
      Current.with_account(accounts(:merovex)) { Record.originate(comment, parent: records(:welcome)) }
    end
  end

  test "a boost broadcasts onto the circle's wall stream; account boosts stay quiet" do
    message = create_discussion(title: "Cheer live")
    sign_in_as users(:bob)

    assert_turbo_stream_broadcasts([ circles(:writers), :wall ], count: 1) do
      perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
        post circle_record_boosts_path(circles(:writers), message.record),
          params: { boost: { content: "🔥" } }
      end
    end

    # Removal broadcasts too (synchronous remove).
    boost = message.record.boosts.first
    assert_turbo_stream_broadcasts([ circles(:writers), :wall ], count: 1) do
      delete circle_boost_path(circles(:writers), boost)
    end

    # An account-side boost (forum message) reaches no wall stream.
    assert_no_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
      records(:welcome).boosts.create!(content: "👍", creator: users(:bob))
    end
  end

  test "a boost from the modal swaps only the strip — the wall stays put" do
    message = create_discussion(title: "Cheer me")
    sign_in_as users(:bob)

    post circle_record_boosts_path(circles(:writers), message.record), params: { boost: { content: "🙌" } }
    # The strip's frame follows this redirect (anchored at the strip) and
    # extracts itself from it.
    assert_match %r{#{circle_message_path(circles(:writers), message.record)}#boosts}, response.location
    assert_equal 1, message.record.boosts.count

    # The wall card now shows the boost itself (read-only — no remove button).
    get circle_path(circles(:writers))
    assert_select ".wall__card .boost", text: /🙌/
    assert_select ".wall__card .boost .boost__remove", 0
  end

  test "a comment posted from the modal streams into place — no modal re-render" do
    message = create_discussion(title: "Discuss me")
    sign_in_as users(:bob)

    post circle_record_comments_path(circles(:writers), message.record),
      params: { back: "wall", comment: { content: "<p>From the modal</p>" } }, as: :turbo_stream

    assert_equal Mime[:turbo_stream], response.media_type
    assert_select %(turbo-stream[action=append][target=modal-comments-list]), 1
    assert_select %(turbo-stream[action=replace][target=wall-thread-composer]), 1
    # No stream re-renders the modal frame itself.
    assert_select %(turbo-stream[target=modal]), 0
    assert_equal 1, message.record.comments.size
  end

  test "without turbo the modal comment falls back to the back=wall redirect" do
    message = create_discussion(title: "Discuss me")
    sign_in_as users(:bob)

    post circle_record_comments_path(circles(:writers), message.record),
      params: { back: "wall", comment: { content: "<p>From the modal</p>" } }
    assert_redirected_to circle_wall_thread_path(circles(:writers), message.record)
  end

  test "a comment on the message page streams in above the composer" do
    message = create_discussion(title: "Discuss me")
    sign_in_as users(:bob)

    post circle_record_comments_path(circles(:writers), message.record),
      params: { comment: { content: "<p>In the thread</p>" } }, as: :turbo_stream

    assert_equal Mime[:turbo_stream], response.media_type
    assert_select %(turbo-stream[action=before][target=new_comment]), 1
    assert_select %(turbo-stream[action=replace][target=new_comment]), 1
  end

  private
    def create_discussion(title:, creator: users(:alice))
      Current.with_bucket(circles(:writers)) do
        message = Message.new(title: title, content: "<p>body</p>", creator: creator,
          status: :published, published_at: Time.current)
        Record.originate(message)
        message
      end
    end
end
