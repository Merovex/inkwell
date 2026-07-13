# Console-only sign-in helpers for operating a deployment without depending on
# email delivery — first-run bootstrap and an email-failure escape hatch. Both
# mint a single-use magic-link code and print it: the plaintext is never stored,
# so printing it on creation is the only way to see it. Run on a server via
# `bin/kamal setup-admin EMAIL=you@example.com` and `bin/kamal rescue-code`.
namespace :auth do
  # Mint a fresh sign-in code for `user` and print it with a redeemable URL.
  def print_sign_in_code(user)
    code = user.sign_in_codes.create!
    url_options = Rails.application.config.action_mailer.default_url_options || {}
    puts "User:  #{user.display_name} (#{user.email_address})"
    puts "Code:  #{SignInCode.format(code.plaintext)}"
    puts "URL:   #{Rails.application.routes.url_helpers.verify_session_url(code: code.plaintext, **url_options)}"
    puts "Expires in #{(SignInCode::EXPIRES_IN / 60).to_i} minutes."
  end

  desc "Create the first user (domain admin) and print a sign-in code — no email sent. EMAIL=you@example.com"
  task setup_admin: :environment do
    abort "Users already exist — use `rescue_code` to sign in as the existing admin." if User.exists?

    email = ENV["EMAIL"].to_s.strip
    abort "Pass the owner's email: EMAIL=you@example.com" if email.empty?

    user = User.new(email_address: email, role: :domain_admin)
    abort "Invalid email: #{user.errors.full_messages.to_sentence}" unless user.save

    puts "Created domain admin. Sign in with the code below (no email required):"
    print_sign_in_code(user)
  end

  desc "Print a fresh sign-in code + verify URL for the root (first/domain admin) user"
  task rescue_code: :environment do
    user = User.domain_admin.order(:id).first || User.order(:id).first
    abort "No users exist yet — run `setup_admin EMAIL=you@example.com` to create the owner." if user.nil?

    print_sign_in_code(user)
  end
end
