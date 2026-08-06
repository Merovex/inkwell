# Build-and-publish one account's static site (docs/hugo-build-pipeline.md):
# Exporter (JSON contract) → Renderer (pinned Hugo) → Publisher (R2 +
# pointer flip). Debounced by scheduling with a delay and serialized per
# account by Solid Queue concurrency, so publish bursts coalesce into few
# builds; full-rebuild-per-publish is the concurrency model — builds are
# cheap by design. A failure alerts (re-raise) and leaves the previous build
# serving: stale, never down.
class SiteBuildJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(account) { account }

  DEBOUNCE = 30.seconds

  # The one enqueue door: publish transitions and Site/design edits call this.
  def self.schedule(account)
    account.update_columns(site_build_status: "queued")
    set(wait: DEBOUNCE).perform_later(account)
  end

  def perform(account)
    account.update_columns(site_build_status: "building")

    workspace = Exporter.new(account, base_url: "https://#{account.public_address}/").export!
    output = Renderer.new(workspace).render!
    Publisher.new(account).publish!(output)

    account.update_columns(site_build_status: "live", site_built_at: Time.current)
  rescue => e
    account.update_columns(site_build_status: "failed")
    raise e # Honeybadger sees it; the previous build keeps serving
  ensure
    FileUtils.rm_rf(workspace) if workspace
  end
end
