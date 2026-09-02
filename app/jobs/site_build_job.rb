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
    account.stamp_build_status!("queued")
    set(wait: DEBOUNCE).perform_later(account)
  end

  def perform(account)
    account.stamp_build_status!("building")

    # The build's canonical home: the custom domain when connected, else the
    # platform host path — the handle when claimed (the Worker resolves it
    # through the handle KV alias), else the slug (served with no KV at all).
    # baseURL and serving location must agree or asset URLs point away from
    # where the reader is; both platform paths serve, links canonicalize
    # toward whichever the build embeds.
    base_url = if account.domain.present?
      "https://#{account.domain}/"
    else
      "https://#{Rails.configuration.x.cloudflare.cname_target}/#{account.handle.presence || account.slug}/"
    end
    workspace = Exporter.new(account, base_url: base_url).export!
    output = Renderer.new(workspace).render!
    Publisher.new(account).publish!(output)

    account.stamp_build_status!("live", built_at: Time.current)
  rescue => e
    account.stamp_build_status!("failed")
    raise e # Honeybadger sees it; the previous build keeps serving
  ensure
    FileUtils.rm_rf(workspace) if workspace
  end
end
