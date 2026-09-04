# Impersonates Sendy's POST /subscribe so BookFunnel's "Sendy" integration can
# push new readers straight onto a site's list (sendy.co/api). BookFunnel only
# sends readers it has confirmed AND holds consent for, so the push carries the
# consent with it — see Subscriber.opt_in_confirmed for what that does and
# deliberately doesn't do.
#
# Authentication, the per-account key and the plain-text answers all come from
# Sendy::BaseController. Success here is "1", or "true" when the caller passes
# boolean=true.
class Sendy::SubscriptionsController < Sendy::BaseController
  # Sendy's exact strings — an impersonation is only as good as its errors.
  MISSING_FIELDS = "Some fields are missing."
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
end
