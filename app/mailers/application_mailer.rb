class ApplicationMailer < ActionMailer::Base
  # Transactional mail sends from the kindredquill.com support identity, walled
  # off from the newsletter's reputation so a bad broadcast can't sink sign-in
  # delivery (ADR 0015).
  default from: "support@kindredquill.com"
  layout "mailer"

  private
    # Newsletter mail sends under Ben Wilson's name from the Postmark-verified
    # merovex.press identity — moved off the old SES sender (news.merovex.press)
    # now that Postmark is the delivery pipe. Uses the `postmark.marketing_from`
    # credential when set, otherwise newsletter@merovex.press. The account's
    # contact address becomes Reply-To on the caller so replies still reach the press.
    def marketing_from(setting)
      address = Rails.application.credentials.dig(:postmark, :marketing_from).presence || "newsletter@merovex.press"
      "Ben Wilson <#{address}>"
    end

    # Bulk newsletter mail (post broadcasts, drip steps) must ride Postmark's
    # Broadcast stream, not the default transactional one — Postmark rejects bulk
    # sends on a transactional stream. Confirmation/sign-in mail sets no stream and
    # so stays on the default `outbound`. Overridable via credentials if the stream
    # is ever renamed.
    def broadcast_stream
      Rails.application.credentials.dig(:postmark, :broadcast_stream).presence || "broadcast"
    end
end
