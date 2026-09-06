require "test_helper"

# Naming where readers come from — plain account-scoped CRUD, domain-admin only.
class AdminPromotionsTest < ActionDispatch::IntegrationTest
  test "promotions are admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_promotions_path
    assert_response :not_found
  end

  test "creating a promotion from a pasted link claims the readers already on it" do
    reader = arrival_from("https://dl.bookfunnel.com/wzpbv5o1z2")
    sign_in_as users(:admin)

    assert_difference -> { Current.account.promotions.count }, 1 do
      post admin_promotions_path, params: { promotion: {
        title: "October SFF", ref: "https://dl.bookfunnel.com/wzpbv5o1z2", shared_on: "2026-10-06"
      } }
    end

    promotion = Current.account.promotions.last
    assert_redirected_to admin_promotion_path(promotion)
    assert_equal "wzpbv5o1z2", promotion.ref
    assert_equal promotion, reader.reload.promotion
    assert_nil reader.attributed_by, "a matched attribution is nobody's assertion"
  end

  test "a promotion with no name is rejected" do
    sign_in_as users(:admin)

    assert_no_difference -> { Promotion.count } do
      post admin_promotions_path, params: { promotion: { title: "", ref: "wzpbv5o1z2" } }
    end
    assert_response :unprocessable_entity
  end

  test "the index lists tokens that brought readers in but have no promotion" do
    arrival_from("https://dl.bookfunnel.com/wzpbv5o1z2")
    sign_in_as users(:admin)

    get admin_promotions_path
    assert_response :success
    assert_select "a[href=?]", new_admin_promotion_path(ref: "wzpbv5o1z2")
  end

  test "the new form arrives prefilled from the index's name-this link" do
    sign_in_as users(:admin)

    get new_admin_promotion_path(ref: "wzpbv5o1z2")
    assert_response :success
    assert_select "input[name=?][value=?]", "promotion[ref]", "wzpbv5o1z2"
  end

  test "the edit form renders" do
    sign_in_as users(:admin)

    get edit_admin_promotion_path(create_promotion(ref: "wzpbv5o1z2"))
    assert_response :success
  end

  test "show lists the promotion's readers" do
    reader = arrival_from("https://dl.bookfunnel.com/wzpbv5o1z2")
    promotion = create_promotion(ref: "wzpbv5o1z2")
    sign_in_as users(:admin)

    get admin_promotion_path(promotion)
    assert_response :success
    assert_select ".subscriber-address__full", text: reader.email_address
  end

  test "removing a promotion leaves its readers on the list" do
    reader = arrival_from("https://dl.bookfunnel.com/wzpbv5o1z2")
    promotion = create_promotion(ref: "wzpbv5o1z2")
    sign_in_as users(:admin)

    assert_no_difference -> { Subscriber.count } do
      delete admin_promotion_path(promotion)
    end
    assert_redirected_to admin_promotions_path
    assert_nil reader.reload.promotion
    assert reader.confirmed?
  end

  test "one site's promotions are invisible to another" do
    other = Account.create!(name: "Someone Else", owner: users(:bob), contact_email: "hi@example.com")
    promotion = Promotion.create!(account: other, creator: users(:bob), title: "Not yours")
    sign_in_as users(:admin)

    get admin_promotion_path(promotion)
    assert_response :not_found
  end

  private
    def arrival_from(source_url, email: "reader@example.com")
      Subscriber.opt_in_confirmed(email_address: email, source: "bookfunnel", source_url: source_url)
    end

    def create_promotion(ref:, title: "October SFF")
      Promotion.create!(account: accounts(:merovex), creator: users(:admin), title: title, ref: ref)
    end
end
