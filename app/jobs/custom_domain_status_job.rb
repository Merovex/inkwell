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
    else
      bridge_routed(account)

      if attempt < MAX_ATTEMPTS
        self.class.set(wait: backoff(attempt)).perform_later(account, attempt: attempt + 1)
      else
        give_up(account)
      end
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
      return unless canonical

      bridge(account, canonical)
      DomainMailer.live(account, canonical).deliver_later
    end

    # Where a site is mounted is a DNS question, not a TLS one. Once the
    # records point here the site is reachable at the domain, and a build still
    # targeting the platform path emits /<handle>/-prefixed asset URLs that 404
    # at the root — a styled-less site. Waiting for the certificate makes that
    # window unbounded: a DV record the author never adds holds provisioning
    # open indefinitely (observed 2026-08-26). Bridging early is safe because a
    # root-based build carries page-relative asset URLs that serve correctly
    # under the platform path too — see Exporter#write_hugo_config.
    def bridge_routed(account)
      return if account.domain.present?

      canonical = account.custom_domains.connected.find_by(canonical: true)
      bridge(account, canonical) if canonical&.diagnosis&.routed?
    end

    # Idempotent: re-bridging the same hostname is no change, so it can't
    # re-trigger the rebuild that saved_change_to_domain? fires.
    def bridge(account, canonical)
      account.update!(domain: canonical.hostname.delete_prefix("www."))
    end

    # The chain stops here, and nothing revisits the row on its own — only the
    # author opening the domains page restarts it (see
    # Admin::CustomDomainsController#repoll_if_stale). Going quiet on a stalled
    # domain is how one sits broken for days, so say so, with the DNS reason
    # already worked out.
    def give_up(account)
      stalled = account.custom_domains.connected.where.not(status: "live")
      Honeybadger.notify("Custom domain never provisioned",
        context: { account_id: account.id,
                   domains: stalled.map { |d|
                     { hostname: d.hostname, status: d.status, cloudflare_status: d.cloudflare_status,
                       ssl_status: d.ssl_status, diagnosis: d.diagnosis.reason }
                   } })
    end

    # Gentle exponential backoff, capped — DV + issuance is usually minutes.
    def backoff(attempt) = [ 30 * (2**(attempt - 1)), 600 ].min.seconds

    def cf_client = self.class.client_override || Cloudflare::Client.new
end
