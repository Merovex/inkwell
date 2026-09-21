# The Export tab of System settings: the author asks for a copy of their site
# (POST creates the Export; ExportJob builds it and emails when it's ready)
# and sees their recent requests. Owner-only on top of the admin gate — the
# archive carries the subscriber list, which isn't platform staff's to take.
class Admin::ExportsController < Admin::BaseController
  include OwnerOnly

  def index
    @exports = Current.account.exports.newest_first.with_attached_archive
  end

  def create
    if Export.request(Current.account)
      redirect_to admin_exports_path, notice: "Building your export — we'll email you when it's ready."
    else
      redirect_to admin_exports_path, alert: "An export is already being built. We'll email you when it's ready."
    end
  end
end
