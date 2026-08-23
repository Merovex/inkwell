require "test_helper"

# The read-only suppression list: this site's readers the platform won't let
# it mail, with reason and scope. Domain-admin only.
class AdminSuppressionsTest < ActionDispatch::IntegrationTest
  test "admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_suppressions_path
    assert_response :not_found
  end

  test "lists suppressions in force for this site's readers, masked by default, and nothing from other sites" do
    sign_in_as users(:admin)
    bounced = Subscriber.create!(email_address: "bounced@example.com", status: :confirmed)
    Suppression.impose!(person: bounced.person, reason: :hard_bounce)
    flagged = Subscriber.create!(email_address: "flagged@example.com", status: :confirmed)
    Suppression.impose!(person: flagged.person, reason: :complaint, scope: accounts(:merovex))
    other = Account.create!(name: "Second Press", owner: users(:bob))
    elsewhere = Subscriber.create!(email_address: "elsewhere@example.com", status: :confirmed)
    Suppression.impose!(person: elsewhere.person, reason: :complaint, scope: other)
    stranger = Person.create!(email_address: "stranger@example.com")
    Suppression.impose!(person: stranger, reason: :hard_bounce)

    get admin_suppressions_path
    assert_response :success
    assert_select "h1", text: "Suppressed addresses"
    assert_select ".subscriber-address__full", text: "bounced@example.com"
    assert_select ".subscriber-address__masked", text: "bou•••@example.com"
    assert_select "td", text: "Every site"
    assert_select ".subscriber-address__full", text: "flagged@example.com"
    assert_select "td", text: "This site"
    assert_select ".subscriber-address__full", text: "elsewhere@example.com", count: 0
    assert_select ".subscriber-address__full", text: "stranger@example.com", count: 0
  end

  test "a lifted suppression drops off the list" do
    sign_in_as users(:admin)
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :bounced)
    Suppression.impose!(person: subscriber.person, reason: :hard_bounce)
    subscriber.reactivate!

    get admin_suppressions_path
    assert_select ".empty__title", text: "Nothing suppressed"
  end

  test "the roster links to the list" do
    sign_in_as users(:admin)

    get admin_subscribers_path
    assert_select "a[href=?]", admin_suppressions_path, text: "Suppressed"
  end
end
