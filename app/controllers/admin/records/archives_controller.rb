# Archiving as a resource, shared by every recordable (posts, messages, books,
# …): POST sets a record aside, DELETE restores it. A permanent, reversible move
# with no purge — separate from the trash. One controller keyed by the Record id,
# mirroring how boosts and comment member actions already work. Manage-only, and
# it redirects back to whichever content type this record is.
class Admin::Records::ArchivesController < Admin::BaseController
  before_action :set_record
  before_action -> { authorize! @record, to: :manage }

  def create
    @record.archive
    redirect_to helpers.record_show_path(@record), notice: "#{noun} archived."
  end

  def destroy
    @record.unarchive
    redirect_to helpers.record_show_path(@record), notice: "#{noun} restored from the archive."
  end

  private
    def set_record
      @record = Current.account.records.active.find(params[:record_id])
    end

    def noun
      @record.recordable_name.capitalize
    end
end
