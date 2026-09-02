require "test_helper"

# The tip-in: email-only rich text spliced into the newsletter at the
# {% tipin %} marker (bookbinding — a page glued in after printing). The
# email gets the splice; every public surface gets neither the tip-in nor
# the marker.
class PostTipinTest < ActiveSupport::TestCase
  setup do
    @post = posts(:kickoff)
    @post.update!(tipin: "<p>Grab the free novella.</p>")
  end

  test "email_content replaces a marker standing on its own line" do
    @post.update!(content: "<p>Before.</p><p>{% tipin %}</p><p>After.</p>")

    html = @post.email_content.to_html
    assert_match "Grab the free novella", html
    assert_no_match Post::TIPIN_MARKER, html
    assert_operator html.index("Grab"), :>, html.index("Before")
    assert_operator html.index("Grab"), :<, html.index("After")
  end

  test "email_content keeps surrounding text when the marker sits inline, splicing after the paragraph" do
    @post.update!(content: "<p>Read on {% tipin %} friends.</p>")

    html = @post.email_content.to_html
    assert_match "Read on  friends", html
    assert_match "Grab the free novella", html
    assert_operator html.index("Grab"), :>, html.index("friends")
  end

  test "a tip-in with no marker lands after the article" do
    @post.update!(content: "<p>The whole post.</p>")

    html = @post.email_content.to_html
    assert_operator html.index("Grab"), :>, html.index("whole post")
  end

  test "a marker with no tip-in vanishes from the email, paragraph and all" do
    post = posts(:typography)
    post.update!(content: "<p>Before.</p><p>{% tipin %}</p>")

    html = post.email_content.to_html
    assert_no_match Post::TIPIN_MARKER, html
    assert_no_match(/<p>\s*<\/p>/, html)
  end

  test "only the first marker gets the tip-in; stragglers just vanish" do
    @post.update!(content: "<p>{% tipin %}</p><p>Middle.</p><p>{% tipin %}</p>")

    html = @post.email_content.to_html
    assert_equal 1, html.scan("Grab the free novella").size
    assert_no_match Post::TIPIN_MARKER, html
  end

  test "the marker forgives spacing — {%tipin%} through {%  tipin  %}" do
    [ "{%tipin%}", "{% tipin %}", "{%tipin %}", "{%  tipin  %}" ].each do |marker|
      @post.update!(content: "<p>#{marker}</p>")

      html = @post.email_content.to_html
      assert_match "Grab the free novella", html, "#{marker} should splice"
      assert_no_match(/\{%/, html, "#{marker} should be consumed")
    end
  end

  test "public_content carries neither the marker nor the tip-in" do
    @post.update!(content: "<p>Before.</p><p>{% tipin %}</p><p>After.</p>")

    html = @post.public_content.to_html
    assert_no_match Post::TIPIN_MARKER, html
    assert_no_match(/Grab the free novella/, html)
    assert_match "Before", html
    assert_match "After", html
  end

  test "summary's body fallback never leaks the marker" do
    @post.update!(content: "<p>{% tipin %}</p><p>Hello world.</p>", excerpt: "")

    assert_equal "Hello world.", @post.summary.strip
  end

  test "the tip-in carries across versions until a save changes it" do
    record = records(:kickoff)
    record.recordable.publish

    carried = record.save_edit(creator: users(:alice), title: "Retitled")
    assert_equal "Grab the free novella.", carried.tipin.to_plain_text

    replaced = record.save_edit(creator: users(:alice), tipin: "<p>New aside.</p>")
    assert_equal "New aside.", replaced.tipin.to_plain_text
    assert_equal "Grab the free novella.", carried.reload.tipin.to_plain_text,
      "old versions keep their own tip-in"
  end
end
