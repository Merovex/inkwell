# The reader-magnet claim page — the tokened landing a drip email's "Get
# {title}" button opens (a Worker-proxied island on the static site, like the
# newsletter token pages). GET only shows format buttons; nothing is spent
# until the download POST, so scanner prefetches are harmless and the page
# survives any number of visits inside the token's life.
class ClaimsController < PublicController
  include IslandProtected
  include ClaimScoped

  # Tokened URLs — minimal layout, which loads no ahoy.js, so a claim visit
  # is never recorded with its token (the subscriptions token pages' choice).
  layout "public_minimal"

  def show
    @grant = resolve_grant(params[:token])

    if @grant.nil?
      # Invalid, expired, or foreign token — one vague page with the renewal
      # form, no oracle about which. The form only mails the address on file.
      render :expired, status: :not_found
    elsif @grant.exhausted?
      render :expired, status: :gone
    else
      @magnet = @grant.magnet
    end
  end
end
