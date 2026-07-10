class SessionMailer < ApplicationMailer
  # Route through the transactional configuration set — bounce/complaint events
  # only, no open/click tracking (SES leaves magic-link mail unmodified).
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :transactional_config_set)
  }

  SUBJECTS = {
    sign_in: "Your Inkwell sign-in link",
    sign_up: "Welcome to Inkwell — confirm your email"
  }.freeze

  # Emails a magic-link sign-in code. `plaintext` is the raw 8-letter code; it
  # lives only in this email — the database stores only its digest. `purpose`
  # (:sign_in / :sign_up) just tunes the subject line.
  def magic_link(user, plaintext, purpose: :sign_in)
    @user = user
    @code = plaintext
    @formatted_code = SignInCode.format(plaintext)
    @verify_url = verify_session_url(code: plaintext)

    mail to: user.email_address, subject: SUBJECTS.fetch(purpose, SUBJECTS[:sign_in])
  end
end
