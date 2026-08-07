# Cloudflare Turnstile keys for the public signup island (bot-protection
# plan). Mirrored config.x-style — same pattern as app_host and
# island_auth_secrets — so tests can swap them without decrypting
# credentials. Sitekey is public (it rides the export contract and baked
# HTML); the secret stays server-side for siteverify. Blank = verification
# off; the static form only renders the widget when the sitekey is present,
# so the widget and the check switch on together.
Rails.application.config.x.turnstile_site_key =
  Rails.application.credentials.dig(:turnstile, :site_key)
Rails.application.config.x.turnstile_secret_key =
  Rails.application.credentials.dig(:turnstile, :secret_key)
