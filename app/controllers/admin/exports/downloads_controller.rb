# Fetching a built export. A POST, like every download here (claims,
# deliveries), so the fetch is counted — but unlike them it never 302s to a
# storage URL: the zip holds the subscriber list, so there is no link that
# works without the owner's session. The file streams through this request.
class Admin::Exports::DownloadsController < Admin::BaseController
  include OwnerOnly
  include ActiveStorage::Streaming

  def create
    export = Current.account.exports.find(params[:export_id])
    return redirect_to(admin_exports_path, alert: "That export has expired — request a fresh one.") unless export.downloadable?

    export.record_download!
    send_blob_stream export.archive.blob, disposition: :attachment
  end
end
