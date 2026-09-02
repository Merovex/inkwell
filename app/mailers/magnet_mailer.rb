# "Send me a new link" — fresh claim links for every magnet the subscriber
# holds a Grant to, requested from an expired claim page (ClaimRenewals).
# Transactional in nature, like the confirmation email: the links are critical
# actions, so this rides the transactional config set and is never
# click-rewritten. The From is still the site's own broadcast address.
class MagnetMailer < ApplicationMailer
  default message_stream: "outbound"

  def renewal(subscriber)
    @site_name = subscriber.account.site.site_name
    url_options = public_url_options(subscriber.account)
    @claims = subscriber.grants.includes(:magnet).map do |grant|
      { title: grant.magnet.title, url: claim_url(token: grant.claim_token, **url_options) }
    end

    magnet_mail(subscriber, subject: "Your #{@site_name} download links")
  end

  # One grant's claim link, re-sent by staff from the roster
  # (Admin::Grants::ClaimRenewals) — same transactional footing as renewal,
  # scoped to the single magnet the reader asked about.
  def claim(grant)
    subscriber = grant.subscriber
    @site_name = subscriber.account.site.site_name
    @title = grant.magnet.title
    @url = claim_url(token: grant.claim_token, **public_url_options(subscriber.account))

    magnet_mail(subscriber, subject: "Your #{@title} download link")
  end

  private
    def magnet_mail(subscriber, subject:)
      setting = subscriber.account.site
      options = { to: subscriber.email_address, subject: subject,
        from: broadcast_from(subscriber.account), delivery_method_options: transactional_options(subscriber.account) }
      options[:reply_to] = setting.contact_email if setting.contact_email.present?
      mail(options)
    end

    def transactional_options(account)
      { configuration_set_name: Rails.application.credentials.dig(:ses, :transactional_config_set),
        **site_tenant_options(account) }
    end
end
