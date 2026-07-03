require "test_helper"

class BoostTest < ActiveSupport::TestCase
  test "requires content" do
    boost = Boost.new(record: records(:kickoff), creator: users(:alice), content: "")
    assert_not boost.valid?
  end

  test "caps content at sixteen characters" do
    boost = Boost.new(record: records(:kickoff), creator: users(:alice), content: "a" * 17)
    assert_not boost.valid?

    boost.content = "💯" * 16
    assert boost.valid?
  end

  test "the same person may boost the same record repeatedly" do
    assert_difference -> { records(:kickoff).boosts.count }, 2 do
      2.times { records(:kickoff).boosts.create!(creator: users(:alice), content: "🙌") }
    end
  end

  test "boosts go down with their record" do
    assert_difference -> { Boost.count }, -2 do
      records(:kickoff).destroy
    end
  end
end
