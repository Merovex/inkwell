class ApplicationMailer < ActionMailer::Base
  # Transactional mail sends from the kindredquill.com support identity, walled
  # off from the newsletter's reputation so a bad broadcast can't sink sign-in
  # delivery (ADR 0015).
  default from: "support@kindredquill.com"
  layout "mailer"

  private
    # Newsletter mail sends under Ben Wilson's name. It uses the SES marketing
    # identity when that credential is set, otherwise falls back to
    # newsletter@merovex.press. The contact address becomes Reply-To on the caller
    # so replies still reach the press.
    def marketing_from(setting)
      address = Rails.application.credentials.dig(:ses, :marketing_from).presence || "newsletter@merovex.press"
      "Ben Wilson <#{address}>"
    end
end
