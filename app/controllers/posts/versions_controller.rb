# A frozen version rendered read-only ("View this version" on the history).
class Posts::VersionsController < ApplicationController
  include PostScoped
  before_action -> { authorize! @record, to: :view }

  def show
    @version = @record.versions.find(params[:id])
  end
end
