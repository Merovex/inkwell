require "test_helper"

class AdminIntegrationsTest < ActionDispatch::IntegrationTest
  test "the tab is admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_integration_path
    assert_response :not_found

    patch admin_integrations_sendy_key_path
    assert_response :not_found
  end

  test "opening the tab mints the key and shows what BookFunnel asks for" do
    account = accounts(:merovex)
    assert_nil account.sendy_api_key
    sign_in_as users(:admin)

    get admin_integration_path

    assert_response :success
    key = account.reload.sendy_api_key
    assert key.present?, "a site that opens the tab is connecting something"
    assert_select "input#sendy_api_key[readonly][value=?]", key
    assert_select "input#sendy_list_id[readonly][value=?]", account.handle.presence || account.slug
    assert_select "input#sendy_host_url[readonly]"
  end

  test "opening the tab twice keeps the same key" do
    sign_in_as users(:admin)

    get admin_integration_path
    was = accounts(:merovex).reload.sendy_api_key
    get admin_integration_path

    assert_equal was, accounts(:merovex).reload.sendy_api_key
  end

  test "rotating replaces the key and says so" do
    account = accounts(:merovex)
    was = account.sendy_api_key!
    sign_in_as users(:admin)

    patch admin_integrations_sendy_key_path

    assert_redirected_to admin_integration_path
    assert_not_equal was, account.reload.sendy_api_key
    assert_match "old one stopped working", flash[:notice]
  end

  test "the key is encrypted at rest" do
    account = accounts(:merovex)
    key = account.sendy_api_key!

    stored = Account.connection.select_value(
      Account.sanitize_sql([ "SELECT sendy_api_key FROM accounts WHERE id = ?", account.id ])
    )
    assert_not_equal key, stored, "the raw key must not sit in the column"
    assert_equal account, Account.find_by(sendy_api_key: key), "and must still be findable by it"
  end
end
