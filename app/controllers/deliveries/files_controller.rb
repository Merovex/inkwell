# Redeem one format from a delivery page: count the (grantless) Download,
# then 302 to a short-lived presigned R2 URL — the file never streams through
# Rails and the page never embeds a file URL. POST on purpose: email scanners
# prefetch GETs, and only a pressed button should mint file URLs. The page is
# ungated by design, so the rate limit is the only spend guard here — the
# capped, audited door is the tokened claim flow.
class Deliveries::FilesController < PublicController
  include IslandProtected
  # In dev/test r2_magnets is a Disk service, and Disk URLs need the request's
  # url_options; the production S3 presigner ignores this.
  include ActiveStorage::SetCurrent

  # Tenant-domain island with no session to anchor CSRF to — same boat as the
  # claim downloads and the static newsletter form.
  skip_forgery_protection

  rate_limit to: 20, within: 3.minutes

  def create
    magnet = Current.account.magnets.find(params[:id])

    # The button posts the chosen format as `kind` — `format` is Rails' own
    # content-negotiation param (and, as a path suffix, would dodge the
    # Worker's island regex).
    file = magnet.file_for(params[:kind].to_s) if params[:kind].to_s.in?(Magnet::FORMATS)
    raise ActiveRecord::RecordNotFound unless file&.attached?

    magnet.downloads.create!(format: params[:kind])
    # Five minutes is plenty for a 302 to complete; expired links die harmlessly.
    redirect_to file.url(expires_in: 5.minutes, disposition: :attachment), allow_other_host: true
  end
end
