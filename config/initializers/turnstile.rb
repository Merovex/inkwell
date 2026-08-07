# The SHARED-FALLBACK Turnstile pair (bot-protection plan): accounts own
# their widgets (TurnstileConnection stamps per-account keys, which take
# precedence — see TurnstileVerifier.site_key_for); this pair covers accounts
# awaiting provisioning via a hand-made widget, and is how dev/test stay off.
# Mirrored config.x-style — same pattern as app_host — so tests can swap
# values without decrypting credentials. Sitekey is public; the secret stays
# server-side for siteverify. Blank = verification off for accounts with no
# widget of their own.
Rails.application.config.x.turnstile_site_key =
  Rails.application.credentials.dig(:turnstile, :site_key)
Rails.application.config.x.turnstile_secret_key =
  Rails.application.credentials.dig(:turnstile, :secret_key)
