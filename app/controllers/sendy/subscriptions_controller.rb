# Impersonates Sendy's POST /subscribe so BookFunnel's "Sendy" integration can
# push new readers straight onto a site's list (sendy.co/api). BookFunnel only
# sends readers it has confirmed AND holds consent for, so the push carries the
# consent with it — see Subscriber.opt_in_confirmed for what that does and
# deliberately doesn't do.
#
# A machine endpoint: inherits ActionController::Base directly, so none of the
# app's browser/auth concerns apply. That matters twice over here — there is no
# session to carry a CSRF token, and ApplicationController's `allow_browser
# versions: :modern` would reject a server-to-server POST that has no browser
# user agent at all. Authenticity is the api_key, nothing else.
#
# The key is per account (Account#sendy_api_key), and it is what decides whose
# list gets written — never the `list` field, which is a form value the caller
# controls. `list` is checked against the key's own account afterwards, so a
# key paired with someone else's list ID is a configuration error we report
# rather than a door into another site.
#
# Sendy's conventions are not REST and are reproduced faithfully: every answer
# is plain text with a 200, including the failures. Success is "1", or "true"
# when the caller passes boolean=true. This controller is the last place
# Sendy's vocabulary exists; everything past it speaks ours.
class Sendy::SubscriptionsController < ActionController::Base
  skip_forgery_protection

  # Sendy's exact strings — an impersonation is only as good as its errors.
  MISSING_FIELDS = "Some fields are missing."
  MISSING_KEY    = "API key not passed"
  INVALID_KEY    = "Invalid API key"
  INVALID_EMAIL  = "Invalid email address."
  INVALID_LIST   = "Invalid list ID."

  # BookFunnel sends YES/NO where Sendy's own docs say true — and casting with
  # ActiveModel's boolean type would read "NO" as true, since it only knows the
  # false-ish spellings. Anything unrecognized stays nil: "we were not told".
  TRUTHY = %w[ true yes y 1 on ].freeze
  FALSY  = %w[ false no n 0 off ].freeze

  # Every reader arriving through this door came from BookFunnel; Sendy's
  # contract has no field that names the integration.
  SOURCE = "bookfunnel"

  before_action :authenticate

  def create
    return render_sendy(MISSING_FIELDS) if params[:email].blank? || params[:list].blank?
    return render_sendy(INVALID_LIST) unless names_the_account?(params[:list])
    return render_sendy(INVALID_EMAIL) if Subscriber.rejection_reason(params[:email])

    subscribe_to(@account)
    # Already subscribed, and an address we may not add back (an opt-out here),
    # both answer success: Sendy would say so itself for the first, and for the
    # second an error would only make BookFunnel retry a decision that stands.
    render_sendy(success)
  rescue ActiveRecord::RecordInvalid
    render_sendy(INVALID_EMAIL)
  end

  private
    # The key identifies the account; there is nothing else to authenticate
    # against. A blank key can't be looked up (every account without a minted
    # key stores NULL, and NULL is not "").
    def authenticate
      presented = params[:api_key].to_s
      return render_sendy(MISSING_KEY) if presented.blank?

      @account = Account.find_by(sendy_api_key: presented)
      render_sendy(INVALID_KEY) if @account.nil?
    end

    def subscribe_to(account)
      Current.with_account(account) do
        Subscriber.opt_in_confirmed(
          email_address: params[:email],
          source: SOURCE,
          # The reader's own IP as the partner recorded it — never
          # request.remote_ip, which is BookFunnel's server and evidences nothing.
          ip: params[:ipaddress].presence,
          country_code: country_code,
          gdpr_country: gdpr_country,
          source_url: params[:referrer].presence
        )
      end
    end

    # The Sendy "list ID" we hand the author is their handle, with the slug
    # accepted too — the same handle-first, slug-fallback shape the sites host
    # and the edge Worker use for a path prefix. It authorizes nothing: this
    # only catches an integration configured with one site's key and another
    # site's list.
    def names_the_account?(list)
      wanted = list.to_s.strip.downcase

      wanted == @account.handle.to_s.downcase.presence ||
        Sluggable.normalize(wanted) == @account.slug
    end

    # Sendy defines `country` as a 2-letter code; BookFunnel also sends its own
    # country_code field, and a `country` spelled out in full ("Portugal") —
    # which is the same fact in a shape this column isn't, so it's dropped.
    def country_code
      code = params[:country_code].presence || params[:country].presence
      code.to_s.upcase if code.to_s.match?(/\A[A-Za-z]{2}\z/)
    end

    # Whether GDPR reaches this reader: Sendy's `gdpr`, or BookFunnel's own
    # is_eu_country / eu_country custom field (their docs: a field with no home
    # on the receiving end is thrown out, and this is the one that must not be).
    def gdpr_country
      flag = params[:gdpr].presence || params[:is_eu_country].presence || params[:eu_country].presence
      value = flag.to_s.strip.downcase
      return true if TRUTHY.include?(value)
      false if FALSY.include?(value)
    end

    def success = TRUTHY.include?(params[:boolean].to_s.downcase) ? "true" : "1"

    # Plain text, HTTP 200, always — Sendy's convention, and BookFunnel reads
    # the body, not the status.
    def render_sendy(body)
      render plain: body
    end
end
