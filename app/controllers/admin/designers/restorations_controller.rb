# Revert the working design to a historical version (the History pane's
# Restore button): the version's payload becomes a fresh draft, and the
# outgoing draft is archived by the save path — restoring never destroys,
# it only adds another version. The designer reloads and boots from the
# restored draft; nothing deploys until the author says so.
class Admin::Designers::RestorationsController < Admin::BaseController
  def create
    version = Current.account.site_design_versions.find(params[:version_id])
    Current.account.restore_design!(version)
    redirect_to admin_designer_path
  end
end
