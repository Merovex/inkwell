# Polls SES for a connecting account's sending domains — the email twin of
# CustomDomainStatusJob — until DKIM and MAIL FROM both verify, then flips the
# rows live and emails the author. Re-enqueues itself with backoff rather than
# looping. A domain whose CNAMEs never land just keeps its "verifying" row
# (the Email tab shows the exact expected records, not a spinner); re-running
# connect re-adopts the identity and restarts the poll.
class SendingDomainStatusJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  # Test seam: a fake Ses::Client, or nil for the real one — a client can't be
  # a job argument (not serializable), so tests set this instead of stubbing.
  cattr_accessor :client_override

  MAX_ATTEMPTS = 20

  def perform(account, attempt: 1)
    verifying = account.sending_domains.where(status: "verifying")
    return if verifying.empty?

    verifying.each { |domain| refresh(domain) }

    if account.sending_domains.connected.where.not(status: "live").none?
      go_live(account)
    elsif attempt < MAX_ATTEMPTS
      self.class.set(wait: backoff(attempt)).perform_later(account, attempt: attempt + 1)
    end
  end

  private
    def refresh(domain)
      identity = ses_client.get_identity(domain.domain)
      # Tokens can rotate on identity re-creation — keep the row's copy honest
      # so the DNS instructions always show what SES actually expects.
      domain.update!(last_checked_at: Time.current,
        dkim_tokens: identity.dkim_tokens.presence || domain.dkim_tokens)
      domain.update!(status: "live") if identity.verified?
    rescue Ses::Client::Error => error
      Rails.logger.warn("[sending-domain] poll failed for #{domain.domain}: #{error.message}")
    end

    def go_live(account)
      domain = account.sending_domains.live.order(:updated_at).last
      DomainMailer.email_live(account, domain).deliver_later if domain
    end

    # Gentle exponential backoff, capped — authors publish DNS on their own
    # clock, so the tail attempts stretch the window without hammering SES.
    def backoff(attempt) = [ 30 * (2**(attempt - 1)), 600 ].min.seconds

    def ses_client = self.class.client_override || Ses::Client.new
end
