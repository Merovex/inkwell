# A frozen version rendered read-only ("View this version" on the history).
class Messages::VersionsController < ApplicationController
  include MessageScoped

  def show
    @version = @record.versions.find(params[:id])
  end
end
