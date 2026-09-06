require "test_helper"

class SubscribersHelperTest < ActionView::TestCase
  include SubscribersHelper

  test "a partner's landing page becomes a link" do
    html = signup_page("https://dl.bookfunnel.com/wzpbv5o1z2")

    assert_includes html, %(href="https://dl.bookfunnel.com/wzpbv5o1z2")
    assert_includes html, %(rel="noopener noreferrer")
  end

  test "a scheme that isn't the web never reaches an href" do
    %w[ javascript:alert(1) data:text/html,hi file:///etc/passwd ].each do |hostile|
      html = signup_page(hostile)

      assert_not_includes html, "href", "#{hostile} was rendered as a link"
      assert_includes html, ERB::Util.html_escape(hostile)
    end
  end

  test "something that isn't a URL at all renders as the text it is" do
    assert_not_includes signup_page("not a url"), "href"
    assert_equal "", signup_page(nil)
  end
end
