require "test_helper"

# Admin CRUD for drip campaigns and their ordered drops. Domain-admin only.
class AdminDripsTest < ActionDispatch::IntegrationTest
  test "drips are admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_drips_path
    assert_response :not_found
  end

  test "the admin pages render" do
    drip = originate_drip
    drop = add_drop(drip, "Welcome", 0)
    sign_in_as users(:admin)

    [ admin_drips_path, new_admin_drip_path, admin_drip_path(drip.record),
      edit_admin_drip_path(drip.record), new_admin_drip_drop_path(drip.record),
      edit_admin_drip_drop_path(drip.record, drop.record) ].each do |path|
      get path
      assert_response :success, "GET #{path}"
    end
  end

  test "creating a drip originates a record and lands on show" do
    sign_in_as users(:admin)

    assert_difference -> { Record.drips.count }, 1 do
      post admin_drips_path, params: { drip: { title: "Welcome", trigger: "confirmed" } }
    end

    drip = Drip.current.find_by(title: "Welcome")
    assert_redirected_to admin_drip_path(drip.record)
  end

  test "adding a drop originates a child record with the next position" do
    drip = originate_drip
    sign_in_as users(:admin)

    assert_difference -> { Record.drops.count }, 1 do
      post admin_drip_drops_path(drip.record),
        params: { drop: { subject: "Hi", delay_days: 0, body: "<p>Welcome</p>" } }
    end

    assert_redirected_to admin_drip_path(drip.record)
    assert_equal 1, drip.drops.first.record.position
  end

  test "reordering rewrites drop positions" do
    drip = originate_drip
    a = add_drop(drip, "A", 1)
    b = add_drop(drip, "B", 2)
    sign_in_as users(:admin)

    patch reorder_admin_drip_path(drip.record), params: { drop_record_ids: [ b.record_id, a.record_id ] }

    assert_response :no_content
    assert_equal 1, b.record.reload.position
    assert_equal 2, a.record.reload.position
  end

  test "activate then deactivate flips the flag as a tracked revision" do
    drip = originate_drip
    sign_in_as users(:admin)

    patch activate_admin_drip_path(drip.record, active: true)
    assert drip.record.reload.recordable.active?

    patch activate_admin_drip_path(drip.record, active: false)
    assert_not drip.record.reload.recordable.active?
  end

  test "destroy trashes the drip" do
    drip = originate_drip
    sign_in_as users(:admin)

    delete admin_drip_path(drip.record)

    assert drip.record.reload.trashed?
  end

  test "the campaign page names who is in it and where each run has got to" do
    drip = originate_drip(active: true)
    add_drop(drip, "Welcome", 0)
    add_drop(drip, "Day two", 1)
    reader = Subscriber.opt_in(email_address: "reader@example.com")
    reader.confirm!            # enrolls
    reader.streams.sole.advance!  # sends day-0, leaves day-1 pending
    sign_in_as users(:admin)

    get admin_drip_path(drip.record)

    assert_response :success
    assert_select ".list__item", 1
    assert_select ".list__item", text: /reader@example.com/
    assert_select ".list__item", text: /1 of 2 sent/
    assert_select ".list__item .badge", text: "In progress"
  end

  test "a run that stopped early says so, and one with no steps left reads finished" do
    drip = originate_drip(active: true)
    add_drop(drip, "Welcome", 0)
    gone = Subscriber.opt_in(email_address: "gone@example.com")
    gone.confirm!
    gone.unsubscribe!  # ends the stream
    sign_in_as users(:admin)

    get admin_drip_path(drip.record)

    assert_select ".list__item .badge", text: "Unsubscribed"

    done = Subscriber.opt_in(email_address: "done@example.com")
    done.confirm!
    done.streams.sole.advance!  # the only drop goes out → nothing left

    get admin_drip_path(drip.record)

    assert_select ".list__item", text: /done@example.com.*1 of 1 sent/m
    assert_select ".list__item .badge", text: "Finished"
  end

  test "a campaign nobody has joined says so instead of an empty list" do
    drip = originate_drip
    add_drop(drip, "Welcome", 0)
    sign_in_as users(:admin)

    get admin_drip_path(drip.record)

    assert_select ".list__item", 0
    assert_select "p", text: /Nobody is in this campaign yet/
  end

  private
    def originate_drip(active: false)
      drip = Drip.new(title: "Welcome", trigger: "confirmed", active: active, creator: users(:admin))
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
