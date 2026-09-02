# Ingests support@kindredquill.com mail as a Missive — email is a second front
# door to the existing support substrate (records, admin digest, read-in-UI,
# reply-from-your-own-client). Pattern adapted from Covenant's TicketsMailbox,
# minus the ticket threading Missives don't need.
#
# Born confirmed: double opt-in exists to guard the OUTBOUND confirmation email
# (a contact form can't make us mail attacker text to a victim), but inbound
# mail sends nothing — the sender proved the address by using it.
#
# No autoresponder, ever: a new message's From is often spam or spoofed, and
# auto-replying to a forged sender is backscatter that burns the reputation the
# whole architecture protects. Malformed/self-sent mail is dropped, not bounced.
#
# Idempotent: SNS is at-least-once; the unique source_message_id index drops
# redeliveries before they can create a second row.
class SupportMailbox < ApplicationMailbox
  # Never ingest our own sending identities (bounce loops, misdirected DSNs).
  OWN_DOMAINS = /(?:\.|@)(?:kindredquill\.com|merovex\.press)\z/i

  # SES writes one of these to the bucket every time a receipt rule is
  # created/updated — operational noise, not support mail.
  SES_SETUP_PROBE = /\Ano-reply-aws@amazon\.com\z/i

  def process
    return if sender_email.blank? || sender_email.match?(OWN_DOMAINS)
    return if sender_email.match?(SES_SETUP_PROBE)

    # Platform mail: no account (the App's inbox), so the tenancy guard needs
    # the deliberate escape hatch (ADR 0017) — and Current.without_account,
    # or the belongs_to default would claim any ambient account for the row.
    Current.without_account do
    Current.allowing_unscoped_tenancy do
      break if mail.message_id.present? &&
               Missive.platform.exists?(source_message_id: mail.message_id)

      Missive.create!(
        account: nil,
        name: sender_name.presence || sender_email,
        email_address: sender_email,
        subject: mail.subject.presence || "(no subject)",
        body: body_text,
        source_message_id: mail.message_id,
        confirmed_at: Time.current
      )
    end
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    # Spam with a 6k-char body or a race on the unique index — drop it quietly.
    Rails.logger.info("SupportMailbox dropped #{mail.message_id}: #{e.message}")
  end

  private
    def sender_email
      @sender_email ||= Array(mail.from).first.to_s.strip.downcase
    end

    def sender_name
      Mail::Address.new(mail[:from]&.value.to_s).display_name
    rescue StandardError
      nil
    end

    # Missive bodies are plain text (5,000 max, read in /admin/missives).
    # Prefer the text part; strip an HTML-only message down to its text.
    def body_text
      text = if (part = mail.text_part)
        part.decoded
      elsif (part = mail.html_part) || mail.mime_type == "text/html"
        Nokogiri::HTML((part || mail).decoded).at_css("body")&.text.to_s
      else
        mail.decoded
      end
      text.to_s.strip.presence&.truncate(5_000) || "(no content)"
    end
end
