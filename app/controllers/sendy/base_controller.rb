# Shared ground for the Sendy-compatible endpoints (sendy.co/api) that a
# reader-magnet partner calls: BookFunnel's "Sendy" integration pushes new
# readers to /subscribe, and asks the .php API below whether the settings work
# and whether a given reader is on the list.
#
# A machine endpoint: inherits ActionController::Base directly, so none of the
# app's browser/auth concerns apply. That matters twice over — there is no
# session to carry a CSRF token, and ApplicationController's `allow_browser
# versions: :modern` would reject a server-to-server POST with no browser user
# agent at all. Authenticity is the api_key, nothing else.
#
# The key is per account (Account#sendy_api_key) and it is what decides WHICH
# site a request reads or writes — never the list field, which is a form value
# the caller controls. Each endpoint checks the list against the key's own
# account afterwards, so a mismatched pair is a configuration error we report
# rather than a door into another site.
#
# Sendy's conventions are not REST and are reproduced faithfully: every answer
# is plain text with a 200, including the failures. These controllers are the
# last place Sendy's vocabulary exists; everything past them speaks ours.
class Sendy::BaseController < ActionController::Base
  # Sendy's exact strings — an impersonation is only as good as its errors.
  MISSING_KEY = "API key not passed"
  INVALID_KEY = "Invalid API key"

  skip_forgery_protection

  before_action :authenticate

  private
    # The key identifies the account; there is nothing else to authenticate
    # against. A blank key can't be looked up (an account with no minted key
    # stores NULL, and NULL is not "").
    def authenticate
      presented = params[:api_key].to_s
      return render_sendy(MISSING_KEY) if presented.blank?

      @account = Account.find_by(sendy_api_key: presented)
      render_sendy(INVALID_KEY) if @account.nil?
    end

    # The "list ID" we hand the author is their handle, with the slug accepted
    # too — the same handle-first, slug-fallback shape the sites host and the
    # edge Worker use for a path prefix. It authorizes nothing: this only
    # catches an integration configured with one site's key and another's list.
    def names_the_account?(list)
      wanted = list.to_s.strip.downcase

      wanted == @account.handle.to_s.downcase.presence ||
        Sluggable.normalize(wanted) == @account.slug
    end

    # Plain text, HTTP 200, always — Sendy's convention, and the caller reads
    # the body, not the status.
    def render_sendy(body)
      render plain: body
    end
end
