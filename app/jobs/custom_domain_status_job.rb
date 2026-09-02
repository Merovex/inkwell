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

  # Long enough to cover a full day. The old ceiling (20 attempts capped at
  # 10 minutes) gave up after ~2.6h, but authors publish DNS on a registrar's
  # clock — often the next day — so every slow author was guaranteed to fall
  # off the end and never be looked at again.
  MAX_ATTEMPTS = 30

  def perform(account, attempt: 1)
    unresolved = account.custom_domains.unresolved
    return if unresolved.empty?

    unresolved.each { |domain| refresh(domain) }

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
      domain.update!(cloudflare_status: hostname.status,
        ssl_status: hostname.ssl_status, last_checked_at: Time.current,
        validation_records: validations_for(domain, hostname))
      domain.update!(status: "live") if domain.provisioned?
    rescue Cloudflare::Client::Error => error
      Rails.logger.warn("[custom-domain] poll failed for #{domain.hostname}: #{error.message}")
    end

    # Cloudflare's list replaces ours outright — that is how a rotated record
    # reaches the author, and how a finished hostname stops advertising a token
    # nobody needs. The one exception is the gap right after creation, when the
    # records aren't minted yet (ssl "initializing"): there an empty answer
    # would blank instructions the author may be halfway through following.
    def validations_for(domain, hostname)
      return hostname.validation_records if hostname.validation_records.any? || hostname.certificate_active?
      domain.validation_records
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
    # author opening the domains page or pressing Check restarts it (see
    # Admin::CustomDomainsController#repoll_if_stale). Alerting us is not
    # enough: the author is the one who has to act, and a row left saying
    # "verifying" tells them something is still happening when nothing is. Mark
    # it so the page can say the watching stopped — the row stays eligible for
    # a later check (CustomDomain::UNRESOLVED_STATUSES), so this is a pause the
    # author can end, not a dead end.
    def give_up(account)
      stalled = account.custom_domains.connected.unresolved
      Honeybadger.notify("Custom domain never provisioned",
        context: { account_id: account.id,
                   domains: stalled.map { |d|
                     { hostname: d.hostname, status: d.status, cloudflare_status: d.cloudflare_status,
                       ssl_status: d.ssl_status, diagnosis: d.diagnosis.reason }
                   } })
      stalled.each { |domain| domain.update!(status: "error") }
    end

    # Gentle exponential backoff, capped at an hour: DV + issuance is usually
    # minutes, but the wait that matters is the author getting to their
    # registrar, so the tail is cheap hourly checks rather than a fast give-up.
    def backoff(attempt) = [ 30 * (2**(attempt - 1)), 1.hour.to_i ].min.seconds

    def cf_client = self.class.client_override || Cloudflare::Client.new
end
