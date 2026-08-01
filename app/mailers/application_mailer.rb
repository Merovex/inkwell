class ApplicationMailer < ActionMailer::Base
  # Transactional mail sends from the kindredquill.com support identity, walled
  # off from the newsletter's reputation so a bad broadcast can't sink sign-in
  # delivery (ADR 0015).
  default from: "support@kindredquill.com"
  layout "mailer"

  private
    # Newsletter mail sends from newsletter@merovex.press under Ben Wilson's name,
    # falling back to the SES marketing identity if the merovex address is unset.
    # The contact address becomes Reply-To on the caller so replies still reach
    # the press.
    def marketing_from(setting)
      address = "newsletter@merovex.press" || Rails.application.credentials.dig(:ses, :marketing_from)
      "Ben Wilson <#{address}>"
    end
end
