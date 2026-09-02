# Deletes the client-controlled IP headers our own infrastructure never sets,
# before ActionDispatch::RemoteIp reads them.
#
# Real traffic reaches Rails as Cloudflare -> edge Worker -> local proxy, and
# only two of those set anything: the Worker writes X-Forwarded-For (and
# X-Island-IP) from CF-Connecting-IP, the proxy appends its own hop. Nothing
# emits Client-IP or the RFC 7239 Forwarded header, so whatever arrives in them
# came from the client — and both are load-bearing:
#
#   - Client-IP disagreeing with X-Forwarded-For makes RemoteIp raise
#     IpSpoofAttackError. Rails::Rack::Logger asks for request.remote_ip on
#     every request, so a scanner sending "Client-IP: 127.0.0.1" (a stock
#     WordPress localhost-bypass probe) 500s any URL it touches.
#   - Rack::Request#forwarded_for prefers Forwarded over X-Forwarded-For, so a
#     client sending it would own request.remote_ip outright — and with it the
#     rate-limit buckets and the consent log (ADR 0011).
#
# Lives in lib/middleware (ignored by autoload) and is required from
# application.rb, because the middleware stack needs the actual class at boot,
# before Zeitwerk.
class ClientIpScrubber
  UNTRUSTED = %w[ HTTP_CLIENT_IP HTTP_FORWARDED ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    UNTRUSTED.each { |header| env.delete(header) }
    @app.call(env)
  end
end
