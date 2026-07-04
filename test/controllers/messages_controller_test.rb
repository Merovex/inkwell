require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "the board lives at /forum and lists posted messages by record id" do
    assert_equal "/forum", messages_path

    get messages_path
    assert_response :success
    assert_select ".list__title", text: messages(:welcome).title
    assert_select "a.list__body[href=?]", message_path(records(:welcome))
    # Drafts stay off the board, behind the counted link.
    assert_select ".list__title", text: messages(:roadmap).title, count: 0
    assert_select "a[href=?]", message_drafts_path
  end

  test "the board byline leads with the category" do
    get messages_path
    assert_select ".list__byline", text: /📢 Announcement by Alice/
  end

  test "show is keyed by the record id, with the category in the byline" do
    get message_path(records(:welcome))
    assert_response :success
    assert_select "h1", text: messages(:welcome).title
    assert_select ".perma-header__content", text: /📢 Announcement by\s+Alice/
  end

  test "the composer offers the category picker and the scheduler" do
    get new_message_path
    assert_response :success
    assert_select "lexxy-editor"
    assert_select "select[name=?]", "message[category_id]" do
      assert_select "option", text: "📢 Announcement"
    end
    assert_select "[popovertarget=scheduler-panel]"
  end

  test "create as draft wraps the message in a record" do
    assert_difference [ "Message.count", "Record.count" ], 1 do
      post messages_path, params: { message: { title: "Hello board", content: "<p>Hi</p>",
        category_id: categories(:question).id } }
    end

    created = Record.order(:id).last
    assert_redirected_to message_path(created)
    assert created.recordable.drafted?
    assert_equal categories(:question), created.recordable.category
  end

  test "create with the Post button publishes immediately" do
    post messages_path, params: { message: { title: "Heads up", content: "<p>!</p>" }, publish: "1" }
    assert Record.order(:id).last.recordable.published?
  end

  test "schedule and save creates a scheduled version and enqueues the publish job" do
    assert_enqueued_with job: Record::PublishLaterJob do
      post messages_path, params: {
        message: { title: "Later", content: "<p>soon</p>" },
        scheduled_posting: "true",
        scheduled_posting_at_date: Date.tomorrow.iso8601,
        scheduled_posting_at_hour: "9"
      }
    end

    assert Record.order(:id).last.recordable.scheduled?
  end

  test "editing a draft mutates in place; editing a posted message versions" do
    assert_no_difference "Message.count" do
      patch message_path(records(:roadmap)), params: { message: { title: "Still a draft" } }
    end
    assert_equal "Still a draft", messages(:roadmap).reload.title

    assert_difference "Message.count", 1 do
      patch message_path(records(:welcome)), params: { message: { title: "Renamed live" } }
    end
    assert_equal "Renamed live", records(:welcome).reload.recordable.title
  end

  test "destroy trashes the record" do
    delete message_path(records(:welcome))
    assert records(:welcome).reload.trashed?
    assert_redirected_to messages_path
  end

  test "the change log narrates message events with message paths" do
    patch message_path(records(:welcome)), params: { message: { title: "Renamed" } }

    get message_events_path(records(:welcome))
    assert_response :success
    assert_select ".history__line", text: /changed the title of this message/
  end
end
