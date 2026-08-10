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

  test "a born-published post schedules the site build" do
    post = Post.new(title: "Hello", creator: users(:admin),
      status: "published", published_at: Time.current)
    assert_enqueued_with(job: SiteBuildJob, args: [ accounts(:merovex) ]) do
      Record.originate(post) # create + publish in one transaction
    end
  end

  test "saving a design draft does not schedule a build; publishing it does" do
    assert_no_enqueued_jobs(only: SiteBuildJob) do
      accounts(:merovex).draft_design.update!(data: { "design" => {} })
    end

    assert_enqueued_with(job: SiteBuildJob, args: [ accounts(:merovex) ]) do
      accounts(:merovex).publish_design!(by: users(:admin))
    end
  end

  test "deploying to preview does not schedule a production build" do
    assert_no_enqueued_jobs(only: SiteBuildJob) do
      PreviewBuildJob.perform_later(accounts(:merovex))
    end
  end

  test "a domain change schedules the site build (go-live stamp and disconnect clear)" do
    assert_enqueued_with(job: SiteBuildJob, args: [ accounts(:merovex) ]) do
      accounts(:merovex).update!(domain: "example.press")
    end
    assert_enqueued_with(job: SiteBuildJob, args: [ accounts(:merovex) ]) do
      accounts(:merovex).update!(domain: nil)
    end
  end
end
