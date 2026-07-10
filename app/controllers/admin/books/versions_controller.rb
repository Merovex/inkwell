# A frozen book version rendered read-only ("View this version" on the history).
class Admin::Books::VersionsController < Admin::BaseController
  include BookScoped
  before_action -> { authorize! @record, to: :view }

  def show
    @version = @record.versions.find(params[:id])
  end
end
