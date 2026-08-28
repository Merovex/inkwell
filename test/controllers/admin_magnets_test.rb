require "test_helper"

# Managing reader magnets — plain account-scoped CRUD, domain-admin only.
class AdminMagnetsTest < ActionDispatch::IntegrationTest
  test "magnet management is admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_magnets_path
    assert_response :not_found
  end

  test "creating a magnet with an epub lands it on the index" do
    sign_in_as users(:admin)

    assert_difference -> { Current.account.magnets.count }, 1 do
      post admin_magnets_path, params: { magnet: {
        title: "The Bargain", description: "A prequel novella.", epub: epub_upload
      } }
    end
    assert_redirected_to admin_magnets_path
  end

  test "a magnet without any file is rejected" do
    sign_in_as users(:admin)

    assert_no_difference -> { Magnet.count } do
      post admin_magnets_path, params: { magnet: { title: "Empty-handed" } }
    end
    assert_response :unprocessable_entity
  end

  test "destroying a magnet takes its grants along" do
    magnet = Magnet.new(title: "The Bargain")
    magnet.epub.attach(io: StringIO.new("epub bytes"), filename: "b.epub", content_type: "application/epub+zip")
    magnet.save!
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    magnet.grant_to(subscriber)
    sign_in_as users(:admin)

    assert_difference [ -> { Magnet.count }, -> { Grant.count } ], -1 do
      delete admin_magnet_path(magnet)
    end
    assert_redirected_to admin_magnets_path
  end

  test "the drop editor only accepts this account's magnets" do
    other = Account.create!(name: "Other Press", owner: users(:alice))
    foreign = Current.with_account(other) do
      Magnet.new(title: "Elsewhere").tap do |magnet|
        magnet.epub.attach(io: StringIO.new("x"), filename: "e.epub", content_type: "application/epub+zip")
        magnet.save!
      end
    end
    sign_in_as users(:admin)

    drip = Drip.new(title: "Welcome", active: true, creator: users(:admin))
    Record.originate(drip)

    post admin_drip_drops_path(drip.record), params: { drop: {
      subject: "Hi", body: "<p>Hello</p>", delay_days: 0, magnet_id: foreign.id
    } }

    drop = drip.drops.sole
    assert_nil drop.magnet_id, "a foreign magnet id must not attach"
  end

  private
    def epub_upload
      Rack::Test::UploadedFile.new(StringIO.new("epub bytes"), "application/epub+zip", original_filename: "the-bargain.epub")
    end
end
