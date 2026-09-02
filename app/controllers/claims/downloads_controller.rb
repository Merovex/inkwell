# Redeem one format of a claimed magnet: count the Download, then 302 to a
# short-lived presigned R2 URL — the file never streams through Rails and the
# claim email never contains a file URL. POST on purpose: email scanners
# prefetch GETs, and only a pressed button may spend the download cap.
class Claims::DownloadsController < PublicController
  include IslandProtected
  include ClaimScoped
  # In dev/test r2_magnets is a Disk service, and Disk URLs need the request's
  # url_options; the production S3 presigner ignores this.
  include ActiveStorage::SetCurrent

  # The claim token IS the authorization — these pages render on tenant
  # domains through the island proxy with no session to anchor CSRF to, same
  # boat as the static newsletter form.
  skip_forgery_protection

  rate_limit to: 20, within: 3.minutes

  layout "public_minimal"

  def create
    grant = resolve_grant(params[:token])
    return render "claims/expired", status: :not_found if grant.nil?
    return render "claims/expired", status: :gone if grant.exhausted?

    # The button posts the chosen format as `kind` — `format` is Rails' own
    # content-negotiation param and would hijack rendering (and, as a path
    # suffix, dodge the Worker's island regex).
    file = grant.magnet.file_for(params[:kind].to_s) if params[:kind].to_s.in?(Magnet::FORMATS)
    raise ActiveRecord::RecordNotFound unless file&.attached?

    grant.downloads.create!(format: params[:kind])
    # Five minutes is plenty for a 302 to complete; expired links die harmlessly.
    redirect_to file.url(expires_in: 5.minutes, disposition: :attachment), allow_other_host: true
  end
end
