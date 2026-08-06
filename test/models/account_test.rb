require "test_helper"

class AccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "slug is generated on create, letter-first, and stable thereafter" do
    account = Account.create!(name: "Second Press", owner: users(:bob))

    assert_match Sluggable::SLUG_FORMAT, account.slug
    assert_equal Sluggable::SLUG_LENGTH, account.slug.length

    slug = account.slug
    account.update!(name: "Renamed Press")
    assert_equal slug, account.reload.slug
  end

  test "find resolves primary key, slug, normalized slug, and to_param form" do
    account = accounts(:merovex)

    assert_equal account, Account.find(account.id)
    assert_equal account, Account.find("TESTAC")
    assert_equal account, Account.find("testac")
    assert_equal account, Account.find("merovex-press-TESTAC")
  end

  test "find normalizes Crockford ambiguity (I/L read as 1, O as 0)" do
    account = Account.create!(name: "Ambiguous", owner: users(:bob))
    account.update_column(:slug, "A10ABC")

    assert_equal account, Account.find("aloabc")
    assert_equal account, Account.find("AIOABC")
  end

  test "to_param is the bare slug" do
    assert_equal "TESTAC", accounts(:merovex).to_param
  end

  test "name and owner are required" do
    assert_not Account.new(owner: users(:bob)).valid?
    assert_not Account.new(name: "No Owner").valid?
  end

  test "domain uniqueness is enforced by the database" do
    assert_raises ActiveRecord::RecordNotUnique do
      Account.create!(name: "Copycat", owner: users(:bob), domain: "merovex.press")
    end
  end

  test "handle normalizes, enforces the limits, and refuses reserved words" do
    account = accounts(:merovex)

    account.update!(handle: "  Merovex  ")
    assert_equal "merovex", account.handle

    assert_not account.update(handle: "ab")               # too short
    assert_not account.update(handle: "-edge-hyphens-")   # bad shape
    assert_not account.update(handle: "has space")
    assert_not account.update(handle: "noreply")          # reserved
    assert account.update(handle: "")                     # un-claim → nil
    assert_nil account.handle
  end

  test "handle is unique across accounts" do
    accounts(:merovex).update!(handle: "merovex")
    other = Account.create_with_owner(name: "Other Press", owner: users(:bob))
    assert_not other.update(handle: "merovex")
  end

  test "ses tenant name derives from the slug; provisioned? follows the stamp" do
    account = accounts(:merovex)
    assert_equal "site-TESTAC", account.ses_tenant_name
    assert_not account.ses_tenant_provisioned?
    account.update!(ses_tenant_provisioned_at: Time.current)
    assert account.ses_tenant_provisioned?
  end

  test "broadcast address prefers the live BYOD domain, then handle, then noreply" do
    account = accounts(:merovex)
    assert_equal "noreply@#{Account.shared_sending_domain}", account.broadcast_address

    account.update!(handle: "merovex")
    assert_equal "merovex@#{Account.shared_sending_domain}", account.broadcast_address

    account.sending_domains.create!(domain: "news.merovex.press", status: "live")
    assert_equal "noreply@news.merovex.press", account.broadcast_address
  end

  test "broadcast_from wraps the address in the site name" do
    assert_match(/\A"?Merovex Press"? <noreply@/, accounts(:merovex).broadcast_from)
  end

  test "suggest_handle offers a base-{4d} variant that is actually free" do
    suggestion = Account.suggest_handle("merovex")
    assert_match(/\Amerovex-\d{4}\z/, suggestion)
    assert_not Account.exists?(handle: suggestion)
  end

  test "a handle change reschedules the build and re-points the edge alias" do
    account = accounts(:merovex)
    assert_enqueued_with(job: SiteBuildJob) do
      assert_enqueued_with(job: HandleRouteJob, args: [ account, nil ]) do
        account.update!(handle: "merovex")
      end
    end
  end
end
