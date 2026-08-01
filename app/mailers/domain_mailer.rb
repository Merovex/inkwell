class DomainMailer < ApplicationMailer
  # Transactional identity/config set, like sign-in mail — bounce/complaint
  # only, no open/click tracking.
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :transactional_config_set)
  }

  # Sent by the status poll once every connected hostname is active and the
  # certificate is deployed (CustomDomainStatusJob#go_live).
  def live(account, domain)
    @account = account
    @domain = domain
    @apex = domain.hostname.delete_prefix("www.")
    mail to: account.owner.email_address, subject: "Your site is live at #{@apex}"
  end
end
