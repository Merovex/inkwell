# "Send me a new link" — fresh claim links for every magnet the subscriber
# holds a Grant to, requested from an expired claim page (ClaimRenewals).
# Transactional in nature, like the confirmation email: the links are critical
# actions, so this rides the transactional config set and is never
# click-rewritten. The From is still the site's own broadcast address.
class MagnetMailer < ApplicationMailer
  default message_stream: "outbound"

  def renewal(subscriber)
    setting = subscriber.account.site
    @site_name = setting.site_name
    url_options = public_url_options(subscriber.account)
    @claims = subscriber.grants.includes(:magnet).map do |grant|
      { title: grant.magnet.title, url: claim_url(token: grant.claim_token, **url_options) }
    end

    options = { to: subscriber.email_address, subject: "Your #{@site_name} download links",
      from: broadcast_from(subscriber.account), delivery_method_options: transactional_options(subscriber.account) }
    options[:reply_to] = setting.contact_email if setting.contact_email.present?
    mail(options)
  end

  private
    def transactional_options(account)
      { configuration_set_name: Rails.application.credentials.dig(:ses, :transactional_config_set),
        **site_tenant_options(account) }
    end
end
