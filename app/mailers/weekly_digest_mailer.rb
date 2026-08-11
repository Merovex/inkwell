# The weekly site digest: one email per user rolling up the sites they own, a
# per-site section each (WeeklyReport). Platform bulk mail like NotificationMailer
# — it's a per-user Inkwell email, not a per-site newsletter, so it rides the
# platform voice and the platform-circles tenant, never a site's sending lane.
class WeeklyDigestMailer < ApplicationMailer
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :marketing_config_set),
    tenant_name: "platform-circles"
  }

  # Takes only serializable args (user, the week's Monday, and which owned
  # sites to render) — WeeklyReport is a PORO, so the caller decides the sites
  # and the mailer just builds their reports. The job passes the changed ones;
  # the in-app "send a test" button passes every owned site.
  def weekly(user, week_of, account_ids)
    @user = user
    @reports = user.owned_accounts.where(id: account_ids)
                   .map { |account| WeeklyReport.new(account, week_of: week_of) }
    @base_url = root_url(**app_url_options).chomp("/")
    @digest_token = user.generate_token_for(:digest_preferences)

    subject = @reports.one? ? "Your week on #{@reports.first.account.name}"
                            : "Your week across #{@reports.size} sites"
    mail to: user.email_address, from: digest_from, subject: subject
  end

  private
    # The digest speaks as the platform's own name: digest@kindredquill.com.
    # Sending as the apex requires the kindredquill.com SES identity to be
    # DKIM-verified AND associated with the platform-circles tenant (rake
    # email:provision handles both; DMARC passes on DKIM alignment, so the
    # apex's SPF -all stays). ENV/credential overridable via ses.digest_from.
    def digest_from
      address = Rails.application.credentials.dig(:ses, :digest_from).presence || "digest@kindredquill.com"
      email_address_with_name(address, "Inkwell")
    end
end
