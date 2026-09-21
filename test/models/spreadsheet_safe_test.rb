require "test_helper"

class SpreadsheetSafeTest < ActiveSupport::TestCase
  test "a cell that would run as a formula is made literal text" do
    %w[ =HYPERLINK("http://evil") +1+1 -2+3 @SUM(A1) ].each do |formula|
      assert_equal "'#{formula}", SpreadsheetSafe.cell(formula)
    end
    assert_equal "'\t=1", SpreadsheetSafe.cell("\t=1")
  end

  test "ordinary text, numbers, times, and nil pass through untouched" do
    now = Time.current
    assert_equal [ "reader@example.com", -5, now, nil ],
      SpreadsheetSafe.row([ "reader@example.com", -5, now, nil ])
  end
end
