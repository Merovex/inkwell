class DomainMailer < ApplicationMailer
  # Transactional identity/config set, like sign-in mail — bounce/complaint
  # only, no open/click tracking; platform-auth tenant, same as the rest of
  # the platform's operational mail.
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :transactional_config_set),
    tenant_name: "platform-auth"
  }

  # Sent by the status poll once every connected hostname is active and the
  # certificate is deployed (CustomDomainStatusJob#go_live).
  def live(account, domain)
    @account = account
    @domain = domain
    @apex = domain.hostname.delete_prefix("www.")
    mail to: account.owner.email_address, subject: "Your site is live at #{@apex}"
  end

  # The email twin: sent by SendingDomainStatusJob#go_live once DKIM and MAIL
  # FROM both verify — the site's broadcasts now send from its own domain.
  def email_live(account, sending_domain)
    @account = account
    @sending_domain = sending_domain
    mail to: account.owner.email_address,
      subject: "Your newsletter now sends from #{sending_domain.domain}"
  end
end
