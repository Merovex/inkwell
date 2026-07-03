# A frozen version rendered read-only ("View this version" on the history).
class Posts::VersionsController < ApplicationController
  include PostScoped

  def show
    @version = @record.versions.find(params[:id])
  end
end
