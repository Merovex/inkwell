require "test_helper"

class CircleWallsTest < ActionDispatch::IntegrationTest
  test "a member sees the wall: cards newest-first, click-through titles" do
    create_discussion(title: "First post")
    create_discussion(title: "Second post")
    sign_in_as users(:bob)

    get circle_wall_path(circles(:writers))
    assert_response :success
    assert_select ".wall__card", 3 # the two above + the fixture discussion
    # Newest first.
    assert_select ".wall__card:first-of-type .wall__title a", text: "Second post"
    assert_select ".wall__title a[href*=?]", "/messages/"
  end

  test "the wall paginates with a lazy frame cursor" do
    12.times { |i| create_discussion(title: "Post #{i}") }
    sign_in_as users(:bob)

    get circle_wall_path(circles(:writers))
    assert_select ".wall__card", 10
    assert_select "turbo-frame[loading=lazy][src*=?]", "before_id"

    # The cursor page carries the rest (2 created + the fixture discussion),
    # no further frame.
    cursor = css_select("turbo-frame[loading=lazy]").first["src"][/before_id=(\d+)/, 1]
    get circle_wall_path(circles(:writers), before_id: cursor)
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

    get circle_wall_path(Circle.commons)
    assert_response :success
    assert_select ".wall__bulletin", text: /Sidebar changes/

    get circle_wall_path(circles(:writers))
    assert_select ".wall__bulletin", 0
  end

  test "a non-member gets the same 404 as a missing circle" do
    outsider = User.create!(email_address: "outsider@example.com")
    sign_in_as outsider
    get circle_wall_path(circles(:writers))
    assert_response :not_found
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
