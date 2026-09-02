# A parsed Turnstile widget `result`: the public sitekey (rides the export
# contract and baked HTML) and the siteverify secret — which the API returns
# ONLY on create, so TurnstileConnection persists both immediately.
module Cloudflare
  class TurnstileWidget
    attr_reader :sitekey, :secret, :domains

    def initialize(result)
      result = result.to_h.deep_stringify_keys
      @sitekey = result["sitekey"]
      @secret = result["secret"]
      @domains = result["domains"]
    end
  end
end
