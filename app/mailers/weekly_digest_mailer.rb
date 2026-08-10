# The weekly site digest: one email per user rolling up the sites they own, a
# per-site section each (WeeklyReport). Platform bulk mail like NotificationMailer
# — it's a per-user Inkwell email, not a per-site newsletter, so it rides the
# platform voice and the platform-circles tenant, never a site's sending lane.
class WeeklyDigestMailer < ApplicationMailer
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :marketing_config_set),
    tenant_name: "platform-circles"
  }

  # Takes only serializable args (user + the week's Monday) so deliver_later can
  # enqueue it — WeeklyReport is a PORO, so the mailer rebuilds the per-site
  # reports here. In production only the sites with something to report are kept;
  # the in-app "send a test" button passes only_changed: false so the owner sees
  # every site rendered. `week_of` is a Date.
  def weekly(user, week_of, only_changed: true)
    @user = user
    reports = user.owned_accounts.map { |account| WeeklyReport.new(account, week_of: week_of) }
    @reports = only_changed ? reports.select(&:changed?) : reports
    @base_url = root_url(**app_url_options).chomp("/")
    @digest_token = user.generate_token_for(:digest_preferences)

    subject = @reports.one? ? "Your week on #{@reports.first.account.name}"
                            : "Your week across #{@reports.size} sites"
    mail to: user.email_address, from: digest_from, subject: subject
  end

  private
    # The digest speaks as the platform, from its own address. ENV/credential
    # overridable; digest@kindredquill.com by default. Sending from the apex
    # needs its own SES/DKIM identity (the web apex can be a static site — mail
    # DNS is separate records).
    def digest_from
      address = Rails.application.credentials.dig(:ses, :digest_from).presence || "digest@kindredquill.com"
      email_address_with_name(address, "Inkwell")
    end
end
