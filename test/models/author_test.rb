require "test_helper"

class AuthorTest < ActiveSupport::TestCase
  test "the first author becomes the default; promoting another demotes it" do
    ben = create_author("Ben Wilson")
    assert ben.reload.default?

    troy = create_author("Troy Buzby")
    assert_not troy.reload.default?

    troy.update!(default: true)
    assert troy.reload.default?
    assert_not ben.reload.default?
    assert_equal troy, Author.default
  end

  test "edits mutate the current version in place — no new row" do
    author = create_author("Ben Wilson")

    assert_no_difference -> { Author.count } do
      author.update!(name: "Ben W.")
    end
    assert_equal "Ben W.", author.record.reload.recordable.name
  end

  test "current returns only live authors" do
    author = create_author("Ben Wilson")
    assert_includes Author.current, author

    author.record.trash
    assert_empty Author.current.where(record_id: author.record_id)
  end

  test "content bylines to the author, falling back to the account holder" do
    author = create_author("Ben Wilson")
    post = posts(:kickoff)

    post.update_column(:author_record_id, author.record_id)
    assert_equal "Ben Wilson", post.reload.byline

    post.update_column(:author_record_id, nil)
    assert_equal post.record.creator.display_name, post.reload.byline
  end

  private
    def create_author(name, **attrs)
      Author.new(name: name, creator: users(:alice), **attrs).tap { |a| Record.originate(a) }
    end
end
