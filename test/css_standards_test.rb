require "test_helper"

# The mechanical half of the css-html-standards skill: raw design values,
# repeated color-mix recipes, and static inline styles fail the build unless
# they're baselined legacy (test/support/css_audit_baseline.txt — shrink it,
# never grow it casually; a new entry should be a deliberate, reviewed choice).
class CssStandardsTest < ActiveSupport::TestCase
  test "author CSS and view markup meet the house standards" do
    output = `#{Rails.root.join("bin/css-audit")} 2>&1`
    assert $?.success?, "bin/css-audit found new violations:\n#{output}"
  end
end
