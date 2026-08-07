# Post-cutover, public traffic reaches Rails through the edge Worker, so the
# connecting peer is a Cloudflare egress IP. Counting Cloudflare as a trusted
# proxy lets ActionDispatch::RemoteIp walk past it to the X-Forwarded-For the
# Worker sets from CF-Connecting-IP — so rate-limit buckets, the consent log
# (ADR 0011), and (once re-enabled) Turnstile's remoteip all see the visitor,
# not the Worker. Bot-protection plan §2.
#
# Ranges from https://www.cloudflare.com/ips/ (stable for years; vendored
# 2026-08-07). The defaults (loopback + RFC1918) stay in the list so dev,
# test, and any local reverse proxy behave exactly as before.
cloudflare_ranges = %w[
  173.245.48.0/20
  103.21.244.0/22
  103.22.200.0/22
  103.31.4.0/22
  141.101.64.0/18
  108.162.192.0/18
  190.93.240.0/20
  188.114.96.0/20
  197.234.240.0/22
  198.41.128.0/17
  162.158.0.0/15
  104.16.0.0/13
  104.24.0.0/14
  172.64.0.0/13
  131.0.72.0/22
  2400:cb00::/32
  2606:4700::/32
  2803:f800::/32
  2405:b500::/32
  2405:8100::/32
  2a06:98c0::/29
  2c0f:f248::/32
].map { |range| IPAddr.new(range) }

Rails.application.config.action_dispatch.trusted_proxies =
  ActionDispatch::RemoteIp::TRUSTED_PROXIES + cloudflare_ranges
