# Archiving a goal as a resource: POST sets it aside (reversible, no purge
# clock), DELETE restores it — the same shape as Admin::Records::ArchivesController.
module Goals
  class ArchivesController < BaseController
    def create
      goal_records.find(params[:goal_id]).archive
      redirect_to goals_path, notice: "Goal archived."
    end

    def destroy
      goal_records.find(params[:goal_id]).unarchive
      redirect_to goals_path, notice: "Goal restored."
    end
  end
end
