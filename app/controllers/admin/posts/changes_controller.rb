# The changes between a past version and the CURRENT one: GET
# /posts/:post_id/changes/:id where :id is the past version. Renders what has
# changed since that version, tracked-changes style.
class Admin::Posts::ChangesController < Admin::BaseController
  include PostScoped
  before_action -> { authorize! @record, to: :view }

  def show
    @version = @record.versions.find(params[:id])
    @current = @record.recordable
  end
end
