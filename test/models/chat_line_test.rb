require "test_helper"

class ChatLineTest < ActiveSupport::TestCase
  test "requires content" do
    line = ChatLine.new(creator: users(:alice), content: "")
    assert_not line.valid?
  end

  test "transcript lists current versions of active line records, oldest first" do
    assert_equal [ chat_lines(:hello_line) ], ChatLine.transcript.to_a

    records(:hello_line).trash
    assert_empty ChatLine.transcript
  end

  test "action-only versions carry the text forward" do
    records(:hello_line).trash
    assert_equal "Morning, everyone!", records(:hello_line).reload.recordable.content.to_plain_text
  end
end
