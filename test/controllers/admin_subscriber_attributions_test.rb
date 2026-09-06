require "test_helper"

# Attributing a reader to a promotion by hand: POST attributes, DELETE undoes.
# The escape hatch for arrivals no token can name — and the record of who said so.
class AdminSubscriberAttributionsTest < ActionDispatch::IntegrationTest
  test "attribution is admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    post admin_subscriber_attribution_path(reader), params: { promotion_id: promotion.id }
    assert_response :not_found
  end

  test "an unattributed reader's card offers the promotions to attribute them to" do
    promotion
    sign_in_as users(:admin)

    get admin_subscriber_path(reader)
    assert_response :success
    assert_select "select#promotion_id option", text: promotion.title
  end

  test "attributing by hand records who did it" do
    sign_in_as users(:admin)

    post admin_subscriber_attribution_path(reader), params: { promotion_id: promotion.id }

    assert_equal promotion, reader.reload.promotion
    assert_equal users(:admin), reader.attributed_by,
      "a hand-made attribution has to be tellable from a measured one"
  end

  test "removing an attribution leaves the reader on the list" do
    reader.update!(promotion: promotion, attributed_by: users(:admin))
    sign_in_as users(:admin)

    assert_no_difference -> { Subscriber.count } do
      delete admin_subscriber_attribution_path(reader)
    end

    assert_nil reader.reload.promotion
    assert_nil reader.attributed_by
    assert reader.confirmed?
  end

  test "a later partner push never overwrites a hand-made attribution" do
    reader.update!(promotion: promotion, attributed_by: users(:admin))

    Subscriber.opt_in_confirmed(email_address: reader.email_address, source: "bookfunnel",
      source_url: "https://dl.bookfunnel.com/s00a53gmdn")

    assert_equal promotion, reader.reload.promotion
    assert_equal users(:admin), reader.attributed_by
  end

  test "a promotion from another site can't be attributed to" do
    other = Account.create!(name: "Someone Else", owner: users(:bob), contact_email: "hi@example.com")
    theirs = Promotion.create!(account: other, creator: users(:bob), title: "Not yours")
    sign_in_as users(:admin)

    post admin_subscriber_attribution_path(reader), params: { promotion_id: theirs.id }
    assert_response :not_found
    assert_nil reader.reload.promotion
  end

  private
    def reader
      @reader ||= Subscriber.create!(email_address: "reader@example.com", status: :confirmed,
        confirmed_at: Time.current)
    end

    def promotion
      @promotion ||= Promotion.create!(account: accounts(:merovex), creator: users(:admin),
        title: "A swap with no link")
    end
end
