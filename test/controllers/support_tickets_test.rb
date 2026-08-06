require "test_helper"

# The App's help desk: tickets bucketed to the requester (Goals pattern),
# threaded with plain Comments; staff work the /admin/tickets queue.
class SupportTicketsTest < ActionDispatch::IntegrationTest
  test "a user opens a ticket, staff get the bell, and the thread is comments" do
    sign_in_as users(:bob)
    users(:admin).update!(role: :root)

    assert_difference -> { Ticket.count } => 1,
                      -> { Notification.where(kind: "ticket_opened", user: users(:admin)).count } => 1 do
      post tickets_path, params: { ticket: { title: "Broken publish button", content: "<p>The button is dead.</p>" } }
    end
    record = Ticket.last.record
    assert_equal users(:bob), record.bucket, "ticket lives on the requester's bucket"

    follow_redirect!
    assert_response :success
    assert_match "Broken publish button", response.body

    # The requester comments on their own ticket.
    assert_difference -> { Comment.count }, 1 do
      post ticket_comments_path(record), params: { comment: { content: "<p>Still broken today.</p>" } }
    end
    assert_equal record.id, Comment.last.record.parent_id
  end

  test "someone else's ticket is indistinguishable from a missing one" do
    sign_in_as users(:bob)
    post tickets_path, params: { ticket: { title: "Mine", content: "<p>私のもの</p>" } }
    record = Ticket.last.record

    stranger = User.create!(name: "Stranger", email_address: "stranger@example.com", role: :member)
    sign_in_as stranger
    get ticket_path(record)
    assert_response :not_found
  end

  test "root staff read any ticket, work the queue, and move status as revisions" do
    sign_in_as users(:bob)
    post tickets_path, params: { ticket: { title: "Weird fonts", content: "<p>Everything is serif?</p>" } }
    record = Ticket.last.record

    users(:admin).update!(role: :root)
    sign_in_as users(:admin)

    get desk_tickets_path
    assert_response :success
    assert_select ".list__title", text: "Weird fonts"

    get ticket_path(record)
    assert_response :success

    assert_difference -> { Ticket.count }, 1 do # a revision, not an edit
      patch desk_ticket_status_path(record, status: "resolved")
    end
    assert_equal "resolved", record.reload.recordable.status
    assert record.recordable.resolved_at.present?

    # Staff reply rings the requester (the replied kind).
    assert_difference -> { Notification.where(kind: "replied", user: users(:bob)).count }, 1 do
      post ticket_comments_path(record), params: { comment: { content: "<p>Fixed — refresh.</p>" } }
    end
  end

  test "the desk is root-only" do
    sign_in_as users(:bob)
    get desk_tickets_path
    assert_response :not_found
  end
end
