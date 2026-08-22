require "test_helper"

# Standing pages on the spine: the slug is identity (it lives on the Record,
# unique per account, permanent), the words are versions like any other
# recordable's.
class PageTest < ActiveSupport::TestCase
  test "the slug comes off the record and addresses the page everywhere" do
    page = accounts(:merovex).page("about")

    assert_equal "about", page.slug
    assert_equal "about", page.to_param
  end

  test "a slug is permanent once set" do
    record = accounts(:merovex).page("about").record

    assert_not record.update(slug: "about-us")
    assert_includes record.errors[:slug].to_s, "can't be changed"
    assert_equal "about", record.reload.slug
  end

  test "one page per slug per account — the database says so" do
    duplicate = Page.new(title: "About again", creator: users(:alice))

    assert_raises ActiveRecord::RecordInvalid do
      Current.with_account(accounts(:merovex)) { Record.originate(duplicate, slug: "about") }
    end
  end

  test "two accounts can each have their own about page" do
    other = Account.create_with_owner(name: "Second Press", owner: users(:bob))

    assert_equal "about", other.page("about").slug
    assert_not_equal accounts(:merovex).page("about").id, other.page("about").id
  end

  test "a new account is seeded with the four standing pages, live and written" do
    account = Account.create_with_owner(name: "Third Press", owner: users(:bob))

    assert_equal Page::MANDATORY.keys.sort, account.pages.map(&:slug).sort
    assert account.pages.all?(&:published?), "pages are live from birth"

    # Live means live: About, Privacy, and Terms open with starter copy rather
    # than publishing three blank pages to the web.
    Page::Starter::SLUGS.each do |slug|
      assert account.page(slug).content.present?, "#{slug} should carry starter copy"
    end
    assert_includes account.page("about").content.to_s, "Third Press"
    # The newsletter band carries its own defaults, so its page starts bare.
    assert account.page("newsletter").content.blank?
  end

  test "editing a published page versions it, like any other publishable" do
    page = accounts(:merovex).page("privacy")

    assert_difference -> { Page.count }, 1 do
      page.record.save_edit(content: "<p>Cookies.</p>", creator: users(:alice))
    end
    assert_includes page.record.reload.recordable.content.to_s, "Cookies."
  end
end
