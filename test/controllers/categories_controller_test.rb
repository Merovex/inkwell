require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "the board's toolbar links to category management" do
    get messages_path
    assert_select ".perma-header__toolbar a[href=?]", categories_path, text: "Edit categories"
  end

  test "index lists categories with edit links" do
    get categories_path
    assert_response :success
    assert_select ".list__title", text: "📢 Announcement"
    assert_select "a.list__body[href=?]", edit_category_path(categories(:announcement))
  end

  test "create adds a category, offered in the composer" do
    assert_difference "Category.count", 1 do
      post categories_path, params: { category: { icon: "💓", name: "Heartbeat" } }
    end
    assert_redirected_to categories_path

    get new_message_path
    assert_select "select[name=?] option", "message[category_id]", text: "💓 Heartbeat"
  end

  test "create rejects a duplicate name" do
    assert_no_difference "Category.count" do
      post categories_path, params: { category: { icon: "📣", name: "Announcement" } }
    end
    assert_response :unprocessable_entity
  end

  test "update renames everywhere — messages reference by id" do
    patch category_path(categories(:announcement)), params: { category: { icon: "📣", name: "News" } }
    assert_redirected_to categories_path

    get message_path(records(:welcome))
    assert_select ".perma-header__content", text: /📣 News by/
  end

  test "a category in use cannot be deleted" do
    assert_no_difference "Category.count" do
      delete category_path(categories(:announcement))
    end
    assert_redirected_to categories_path
    assert_match "in use", flash[:alert]
  end

  test "an unused category deletes outright" do
    unused = Category.create!(icon: "🎯", name: "Goal")

    assert_difference "Category.count", -1 do
      delete category_path(unused)
    end
    assert_redirected_to categories_path
  end
end
