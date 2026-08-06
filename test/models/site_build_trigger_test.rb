require "test_helper"

# Publish-visible transitions on a Site's content enqueue the static build;
# draft churn does not (docs/phase-2-static-serving.md §2.3).
class SiteBuildTriggerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "publishing a post schedules the site build; a draft does not" do
    post = Post.new(title: "Hello", creator: users(:admin))
    assert_no_enqueued_jobs(only: SiteBuildJob) do
      Record.originate(post) # a draft — no build
    end

    assert_enqueued_with(job: SiteBuildJob, args: [ accounts(:merovex) ]) do
      post.publish(creator: users(:admin))
    end
  end

  test "a saved design schedules the site build" do
    assert_enqueued_with(job: SiteBuildJob, args: [ accounts(:merovex) ]) do
      accounts(:merovex).update!(design: { "design" => {} })
    end
  end
end
