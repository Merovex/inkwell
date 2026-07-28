require "test_helper"

class AccountTest < ActiveSupport::TestCase
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
end
