require "test_helper"

class SvgTest < ActiveSupport::TestCase
  test "aspect ratio comes from the viewBox" do
    assert_equal 3.0, Svg.aspect_ratio(%(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 40"></svg>))
    assert_equal 3.0, Svg.aspect_ratio(%(<svg viewBox="0,0,120,40"></svg>)), "comma-separated viewBox"
  end

  test "falls back to width/height attributes" do
    assert_equal 2.0, Svg.aspect_ratio(%(<svg width="64" height="32"></svg>))
    assert_equal 2.0, Svg.aspect_ratio(%(<svg width="64px" height="32px"></svg>))
  end

  test "nil when the file declares no usable size" do
    assert_nil Svg.aspect_ratio(%(<svg xmlns="http://www.w3.org/2000/svg"></svg>))
    assert_nil Svg.aspect_ratio(%(<svg viewBox="0 0 120 0"></svg>)), "zero height"
    assert_nil Svg.aspect_ratio("not an svg at all")
  end
end
