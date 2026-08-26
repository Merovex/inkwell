# Polls Cloudflare for a connecting account's custom hostnames (step 5) until
# every one is live — result.status AND result.ssl.status both active — then
# flips the rows, bridges the legacy account.domain, and emails the author.
# Re-enqueues itself with backoff rather than looping, so a slow DV validation
# doesn't hold a worker. A hostname whose TXT never lands just keeps its
# "verifying" row (the UI shows the exact expected TXT, not a spinner).
class CustomDomainStatusJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  # Test seam: a fake Cloudflare client, or nil for the real one. A client can't
  # be a job argument (not serializable), so tests set this instead of stubbing.
  cattr_accessor :client_override

  MAX_ATTEMPTS = 20

  def perform(account, attempt: 1)
    verifying = account.custom_domains.where(status: "verifying")
    return if verifying.empty?

    verifying.each { |domain| refresh(domain) }

    if account.custom_domains.connected.where.not(status: "live").none?
      go_live(account)
    elsif attempt < MAX_ATTEMPTS
      self.class.set(wait: backoff(attempt)).perform_later(account, attempt: attempt + 1)
    end
  end

  private
    def refresh(domain)
      hostname = cf_client.get_custom_hostname(domain.cloudflare_id)
      # Cloudflare mints the DV-TXT record asynchronously (ssl "initializing"
      # at creation) — backfill it so the DNS instructions can render.
      domain.update!(cloudflare_status: hostname.status,
        ssl_status: hostname.ssl_status, last_checked_at: Time.current,
        txt_name: hostname.txt_name || domain.txt_name,
        txt_value: hostname.txt_value || domain.txt_value)
      domain.update!(status: "live") if domain.provisioned?
    rescue Cloudflare::Client::Error => error
      Rails.logger.warn("[custom-domain] poll failed for #{domain.hostname}: #{error.message}")
    end

    # Certificate deployed and hostname proxied for every row. Bridge the
    # canonical apex onto account.domain so the existing host resolution and
    # apex→domain redirect keep working, then tell the author.
    def go_live(account)
      canonical = account.custom_domains.connected.find_by(canonical: true)
      account.update!(domain: canonical.hostname.delete_prefix("www.")) if canonical
      DomainMailer.live(account, canonical).deliver_later if canonical
    end

    # Gentle exponential backoff, capped — DV + issuance is usually minutes.
    def backoff(attempt) = [ 30 * (2**(attempt - 1)), 600 ].min.seconds

    def cf_client = self.class.client_override || Cloudflare::Client.new
end
