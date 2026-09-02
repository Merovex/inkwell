require "test_helper"

class HostnameTest < ActiveSupport::TestCase
  test "normalises scheme, path, port, case, and stray dots" do
    assert_equal "merovex.press", Hostname.new("HTTPS://Merovex.Press/blog/").normalized
    assert_equal "merovex.press", Hostname.new("  merovex.press.  ").normalized
    assert_equal "merovex.press", Hostname.new("merovex.press:443").normalized
    assert_equal "merovex.press", Hostname.new("http://merovex.press?utm=x").normalized
  end

  test "onboarding set, canonical, and apex cover apex + www" do
    h = Hostname.new("www.merovex.press")
    assert h.valid?
    assert_equal %w[merovex.press www.merovex.press], h.onboarding_set
    assert_equal "www.merovex.press", h.canonical
    assert_equal "merovex.press", h.apex
  end

  test "rejects our own namespace" do
    assert_not Hostname.new("kindredquill.com").valid?
    assert_not Hostname.new("anything.kindredquill.com").valid?
  end

  test "rejects blanks, junk, and non-ascii (must be punycode)" do
    assert_not Hostname.new("").valid?
    assert_not Hostname.new("not a domain").valid?
    assert_not Hostname.new("nodot").valid?
    assert_not Hostname.new("mérovex.press").valid?
  end

  test "accepts a plain registrable domain" do
    assert Hostname.new("merovex.press").valid?
    assert Hostname.new("sub.example.co.uk").valid?
  end
end
