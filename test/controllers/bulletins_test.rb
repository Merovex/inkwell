require "test_helper"

class BulletinsTest < ActionDispatch::IntegrationTest
  def originate_bulletin(published: true)
    bulletin = Bulletin.new(title: "Sidebar changes", content: "<p>Details.</p>",
      creator: users(:alice), event: :created)
    Record.originate(bulletin)
    bulletin.publish(creator: users(:alice)) if published
    bulletin.record
  end

  test "root authors a bulletin from the support desk" do
    sign_in_as users(:alice) # root
    get support_bulletins_path
    assert_response :success

    post support_bulletins_path, params: { bulletin: { title: "Big news", content: "<p>Soon.</p>" }, publish: "1" }
    assert_redirected_to support_bulletins_path
    assert Bulletin.exists?(title: "Big news", status: "published")
    assert_nil Bulletin.find_by(title: "Big news").record.bucket
  end

  test "the desk is a 404 for members" do
    sign_in_as users(:bob)
    get support_bulletins_path
    assert_response :not_found
    post support_bulletins_path, params: { bulletin: { title: "Nope", content: "x" } }
    assert_response :not_found
  end

  test "any signed-in user reads a published bulletin" do
    record = originate_bulletin
    sign_in_as users(:bob)

    get bulletins_path
    assert_response :success
    assert_select "h3", text: "Sidebar changes"

    get bulletin_path(record.to_slug)
    assert_response :success
    assert_select "h1", text: "Sidebar changes"
    assert_match "An announcement from", response.body
  end

  test "drafts are invisible to members but previewable by root" do
    record = originate_bulletin(published: false)

    sign_in_as users(:bob)
    get bulletin_path(record.id)
    assert_response :not_found

    sign_in_as users(:alice)
    get bulletin_path(record.id)
    assert_response :success
  end
end
