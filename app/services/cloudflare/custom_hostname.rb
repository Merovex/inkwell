# A parsed Cloudflare custom-hostname `result`: the id we persist and poll, the
# two statuses that gate "live" (hostname `status` and certificate `ssl.status`),
# and the DV-TXT record the author must create. Cloudflare has carried the TXT
# under ssl.validation_records[] and, on older responses, directly on ssl — we
# read whichever is present.
module Cloudflare
  class CustomHostname
    attr_reader :id, :hostname, :status, :ssl_status, :txt_name, :txt_value

    def initialize(result)
      result = result.to_h.deep_stringify_keys
      @id = result["id"]
      @hostname = result["hostname"]
      @status = result["status"]
      ssl = result["ssl"] || {}
      @ssl_status = ssl["status"]
      record = Array(ssl["validation_records"]).first || ssl
      @txt_name = record["txt_name"]
      @txt_value = record["txt_value"]
    end

    # Both green: Cloudflare will proxy the hostname AND the certificate is
    # deployed. A TLS handshake can pass before ssl flips, so we require both.
    def active? = status == "active" && ssl_status == "active"
  end
end
