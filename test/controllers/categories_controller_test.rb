require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
  end

  test "category management is admin-only: members get the 404, and no toolbar link" do
    sign_in_as users(:alice)

    get admin_categories_path
    assert_response :not_found

    assert_no_difference "Category.count" do
      post admin_categories_path, params: { category: { icon: "💥", name: "Sneaky" } }
    end
    assert_response :not_found

    get admin_messages_path
    assert_select ".perma-header__toolbar a[href=?]", admin_categories_path, count: 0
  end

  test "the board's toolbar links the admin to category management" do
    get admin_messages_path
    assert_select ".perma-header__toolbar a[href=?]", admin_categories_path, text: "Edit categories"
  end

  test "index lists categories with edit links" do
    get admin_categories_path
    assert_response :success
    assert_select ".list__title", text: "📢 Announcement"
    assert_select "a.list__body[href=?]", edit_admin_category_path(categories(:announcement))
  end

  test "create adds a category, offered in the composer" do
    assert_difference "Category.count", 1 do
      post admin_categories_path, params: { category: { icon: "💓", name: "Heartbeat" } }
    end
    assert_redirected_to admin_categories_path

    get new_admin_message_path
    assert_select "select[name=?] option", "message[category_id]", text: "💓 Heartbeat"
  end

  test "create rejects a duplicate name" do
    assert_no_difference "Category.count" do
      post admin_categories_path, params: { category: { icon: "📣", name: "Announcement" } }
    end
    assert_response :unprocessable_entity
  end

  test "create rejects an over-long name or icon" do
    assert_no_difference "Category.count" do
      post admin_categories_path, params: { category: { icon: "📣", name: "N" * 65 } }
    end
    assert_response :unprocessable_entity

    assert_no_difference "Category.count" do
      post admin_categories_path, params: { category: { icon: "x" * 17, name: "Fine" } }
    end
    assert_response :unprocessable_entity
  end

  test "update renames everywhere — messages reference by id" do
    patch admin_category_path(categories(:announcement)), params: { category: { icon: "📣", name: "News" } }
    assert_redirected_to admin_categories_path

    get admin_message_path(records(:welcome))
    assert_select ".perma-header__content", text: /📣 News by/
  end

  test "a category in use cannot be deleted" do
    assert_no_difference "Category.count" do
      delete admin_category_path(categories(:announcement))
    end
    assert_redirected_to admin_categories_path
    assert_match "in use", flash[:alert]
  end

  test "an unused category deletes outright" do
    unused = Category.create!(icon: "🎯", name: "Goal")

    assert_difference "Category.count", -1 do
      delete admin_category_path(unused)
    end
    assert_redirected_to admin_categories_path
  end
end
