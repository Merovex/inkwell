InvisibleCaptcha.setup do |config|
  # The honeypot (a hidden field bots fill in) runs everywhere. The two
  # session-backed traps — the time-to-submit timestamp and the spinner — are
  # planted when the form renders, so they're disabled in tests to let specs
  # POST directly; the honeypot still covers the spam path.
  config.timestamp_enabled = !Rails.env.test?
  config.spinner_enabled = !Rails.env.test?
end
