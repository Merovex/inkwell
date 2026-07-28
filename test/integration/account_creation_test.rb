require "test_helper"

# A signed-in user founds a press: unique name, owner_id-based superuser
# authority (global role stays member), membership row, landing in the new
# account's admin.
class AccountCreationTest < ActionDispatch::IntegrationTest
  APP_HOST = "app.kindredquill.example"

  setup do
    Rails.configuration.x.app_host = APP_HOST
    @founder = User.create!(email_address: "founder@example.com")
    host! APP_HOST
    sign_in_as @founder
  end

  teardown do
    Rails.configuration.x.app_host = nil
  end

  test "creating a press makes the user its owner-member and lands in its admin" do
    assert_difference [ "Account.count", "AccountUser.count" ], 1 do
      post accounts_path, params: { account: { name: "Founder Press" } }
    end

    account = Account.find_by(name: "Founder Press")
    assert_equal @founder, account.owner
    assert account.member?(@founder)
    assert_redirected_to "http://#{APP_HOST}/#{account.slug}/admin"

    follow_redirect!
    assert_response :success, "a plain-member owner administers their own press"
  end

  test "a taken or blank name re-renders with errors, creating nothing" do
    assert_no_difference [ "Account.count", "AccountUser.count" ] do
      post accounts_path, params: { account: { name: accounts(:merovex).name.upcase } }
      assert_response :unprocessable_entity

      post accounts_path, params: { account: { name: "" } }
      assert_response :unprocessable_entity
    end
  end

  test "the picker's empty state offers press creation" do
    get "/"
    assert_response :success
    assert_select "a[href=?]", new_account_path, text: "Create a press"
  end

  test "an owner cannot administer someone else's press" do
    post accounts_path, params: { account: { name: "Founder Press" } }

    get "/#{accounts(:merovex).slug}/admin/books"
    assert_response :not_found
  end
end
