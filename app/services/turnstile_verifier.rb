require "net/http"

# Server-side Cloudflare Turnstile check (siteverify) for the public signup
# island. Fail closed: anything short of an affirmative success — missing
# token, rejected token, timeout, Cloudflare outage — is unverified, which
# protects sender reputation during an outage at the cost of losing real
# signups in that rare window (bot-protection plan, "Decisions locked").
#
# Keys resolve account-first (the widget TurnstileConnection provisioned),
# falling back to the shared config.x pair (config/initializers/turnstile.rb)
# so a hand-made widget can still cover accounts awaiting provisioning. Both
# blank = verification off; the static form only renders the widget when a
# sitekey rides the export contract, so the widget and check switch on
# together, per account.
#
# remote_ip is deliberately NOT sent yet: until the Worker forwards the real
# client IP (plan §2), request.remote_ip is the Worker's egress IP, and a
# mismatched remoteip fails siteverify — which fail-closed would turn into
# blocking everyone.
class TurnstileVerifier
  VERIFY_URL = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")
  TIMEOUT = 5 # seconds — a hung siteverify must not hold the request hostage

  def self.site_key_for(account)
    account&.turnstile_site_key.presence || Rails.configuration.x.turnstile_site_key
  end

  def self.secret_key_for(account)
    account&.turnstile_secret_key.presence || Rails.configuration.x.turnstile_secret_key
  end

  def initialize(token, account: nil)
    @token = token
    @secret = self.class.secret_key_for(account)
  end

  def verified?
    return true if @secret.blank?
    return false if @token.blank?

    siteverify["success"] == true
  rescue StandardError => error
    Rails.logger.warn("[turnstile] siteverify failed (#{error.class}: #{error.message}) — failing closed")
    false
  end

  private
    def siteverify
      http = Net::HTTP.new(VERIFY_URL.host, VERIFY_URL.port)
      http.use_ssl = true
      http.open_timeout = http.read_timeout = http.write_timeout = TIMEOUT
      response = http.post(VERIFY_URL.path, URI.encode_www_form(secret: @secret, response: @token))
      JSON.parse(response.body)
    end
end
