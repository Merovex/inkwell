require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "post_length counts words and estimates the read at ~225 wpm" do
    assert_equal "3 words, about 1 minute", post_length(rich_text("One two three"))
    assert_equal "450 words, about 2 minutes", post_length(rich_text(("word " * 450)))
  end

  test "post_length counts across block boundaries, not through them" do
    # <p>one</p><p>two</p> is two words — a naive text join would make it one.
    assert_equal "2 words, about 1 minute", post_length(rich_text("<p>one</p><p>two</p>"))
  end

  test "post_length skips the reading estimate for an empty body" do
    assert_equal "0 words", post_length(rich_text(""))
  end

  test "post_length accepts plain text a caller already extracted" do
    assert_equal "3 words, about 1 minute", post_length("One two three")
  end

  test "plain_excerpt truncates on a word boundary" do
    assert_equal "one two...", plain_excerpt(rich_text("one two three"), length: 10)
  end

  private
    def rich_text(html)
      ActionText::RichText.new(body: html)
    end
end
