class ApplicationMailer < ActionMailer::Base
  # Transactional mail sends from the auth.merovex.press identity, which signs
  # with its own DKIM — walled off from the newsletter's news.merovex.press
  # reputation so a bad broadcast can't sink sign-in delivery (ADR 0015).
  default from: Rails.application.credentials.dig(:ses, :transactional_from) || "noreply@example.com"
  layout "mailer"

  private
    # Newsletter mail must send from the news.merovex.press identity so it signs
    # with that DKIM (SES rejects a From on any unverified domain). The press's
    # name rides along as the friendly display label; the contact address becomes
    # Reply-To on the caller so replies still reach the press.
    def marketing_from(setting)
      address = Rails.application.credentials.dig(:ses, :marketing_from) || "noreply@example.com"
      setting.site_name.present? ? "#{setting.site_name} <#{address}>" : address
    end
end
