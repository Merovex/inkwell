require "test_helper"

# The drip overview dashboard: tiles, history, and upcoming sends.
class AdminDripDashboardTest < ActionDispatch::IntegrationTest
  test "dashboard is admin-only" do
    sign_in_as users(:bob)
    get dashboard_admin_drips_path
    assert_response :not_found
  end

  test "renders the tiles and an upcoming send" do
    drip = originate_drip(active: true)
    add_drop(drip, "Welcome", 0)
    add_drop(drip, "Day three", 3)
    sub = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    stream = drip.enroll(sub)
    stream.advance!  # sends day-0, leaves day-3 pending → one upcoming

    sign_in_as users(:admin)
    get dashboard_admin_drips_path

    assert_response :success
    assert_select ".drip-stat__num", text: "1"          # at least the delivered/active tiles read 1
    assert_select ".mrow__label", text: "reader@example.com"
  end

  private
    def originate_drip(active:)
      drip = Drip.new(title: "Welcome", active:, trigger: "confirmed", creator: users(:admin))
      Record.originate(drip)
      drip
    end

    def add_drop(drip, subject, delay_days)
      drop = Drop.new(subject:, delay_days:, creator: users(:admin))
      drop.body = "<p>#{subject}</p>"
      Record.originate(drop, parent: drip.record)
      drop.record.update!(position: delay_days + 1)
      drop
    end
end
