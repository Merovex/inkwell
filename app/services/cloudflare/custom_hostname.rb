# A parsed Cloudflare custom-hostname `result`: the id we persist and poll, the
# two statuses that gate "live" (hostname `status` and certificate `ssl.status`),
# and the DV-TXT records the author must create. Cloudflare has carried the TXT
# under ssl.validation_records[] and, on older responses, directly on ssl — we
# read whichever is present.
module Cloudflare
  class CustomHostname
    attr_reader :id, :hostname, :status, :ssl_status, :validation_records

    def initialize(result)
      result = result.to_h.deep_stringify_keys
      @id = result["id"]
      @hostname = result["hostname"]
      @status = result["status"]
      ssl = result["ssl"] || {}
      @ssl_status = ssl["status"]
      # Every outstanding record, not just the first. Cloudflare lists one per
      # in-flight validation attempt, so a rotated order leaves two pending and
      # the certificate issues only when BOTH are published — reading `.first`
      # here is what hid the blocking record from the author's DNS instructions.
      @validation_records = CustomDomain::ValidationRecord.wrap(
        Array(ssl["validation_records"]).presence || [ ssl ]
      )
    end

    # Both green: Cloudflare will proxy the hostname AND the certificate is
    # deployed. A TLS handshake can pass before ssl flips, so we require both.
    def active? = status == "active" && ssl_status == "active"

    # Cloudflare stops listing validation records once the certificate issues,
    # so an empty list means two different things — "nothing left to publish"
    # and "not minted yet". This is what tells them apart.
    def certificate_active? = ssl_status == "active"
  end
end
