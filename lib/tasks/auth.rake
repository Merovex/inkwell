# Emergency sign-in for when email delivery fails. Mints a fresh single-use
# magic-link code for the root user (the first user ever / domain admin) and
# prints it to the console — the plaintext is never stored, so this is the only
# way to recover it. Run on a server via: bin/kamal rescue-code
namespace :auth do
  desc "Print a fresh sign-in code + verify URL for the root (first/domain admin) user"
  task rescue_code: :environment do
    user = User.domain_admin.order(:id).first || User.order(:id).first
    abort "No users exist yet — visit /setup to create the owner account." if user.nil?

    code = user.sign_in_codes.create!
    url_options = Rails.application.config.action_mailer.default_url_options || {}
    puts "User:  #{user.display_name} (#{user.email_address})"
    puts "Code:  #{SignInCode.format(code.plaintext)}"
    puts "URL:   #{Rails.application.routes.url_helpers.verify_session_url(code: code.plaintext, **url_options)}"
    puts "Expires in #{(SignInCode::EXPIRES_IN / 60).to_i} minutes."
  end
end
