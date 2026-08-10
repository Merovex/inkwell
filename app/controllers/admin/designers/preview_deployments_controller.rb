# Deploy the draft design to the staging host (preview.kindredquill.com/
# <handle>/) so the author can share it for a second opinion before promoting
# to production. Explicit and repeatable — each create rebuilds the preview
# from the latest saved draft; nothing here touches the live site.
class Admin::Designers::PreviewDeploymentsController < Admin::BaseController
  def create
    PreviewBuildJob.perform_later(Current.account)
    head :no_content
  end
end
