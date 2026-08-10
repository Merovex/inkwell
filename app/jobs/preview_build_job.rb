# Build-and-publish one account's DRAFT design to the staging host
# (preview.kindredquill.com/<handle||slug>/) so the author can get a second
# opinion before promoting. Same Exporter → Renderer → Publisher pipeline as
# SiteBuildJob, but it reads the draft design and lands in the preview
# channel, so production is never touched. Deploys are explicit (the author
# clicks "Deploy to preview"), and serialized per account so a burst of
# re-deploys coalesces into the latest draft.
class PreviewBuildJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(account) { account }

  def perform(account)
    # baseURL and serving location must agree; relativeURLs (Exporter) keeps
    # the assets portable under the handle path prefix on the staging host.
    workspace = Exporter.new(account, design: account.draft_design&.data, base_url: account.preview_url).export!
    output = Renderer.new(workspace).render!
    Publisher.new(account, channel: :preview).publish!(output)
  ensure
    FileUtils.rm_rf(workspace) if workspace
  end
end
