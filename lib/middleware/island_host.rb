# Restores the tenant host on Worker-proxied island requests. The edge Worker
# forwards the original host, but X-Forwarded-Host doesn't survive the trip —
# the proxy hops in front of Rails rewrite it from the Host header (the
# origin's own name), which routed island requests to the app host and 404'd
# them. So the Worker also sends the tenant host as X-Island-Host, a header
# nothing else touches, and this middleware copies it into X-Forwarded-Host —
# but ONLY when the island-auth secret validates, so an attacker can't spoof
# a tenant host at the origin. Runs before AccountHost::Extractor, which then
# resolves the account exactly as if the request had hit the tenant domain.
module IslandHost
  class Rewriter
    def initialize(app)
      @app = app
    end

    def call(env)
      host = env["HTTP_X_ISLAND_HOST"]
      env["HTTP_X_FORWARDED_HOST"] = host if host.present? && authentic?(env)
      @app.call(env)
    end

    private
      def authentic?(env)
        secrets = Array(Rails.configuration.x.island_auth_secrets)
        presented = env["HTTP_X_ISLAND_AUTH"].to_s
        secrets.any? { |secret| ActiveSupport::SecurityUtils.secure_compare(presented, secret) }
      end
  end
end
