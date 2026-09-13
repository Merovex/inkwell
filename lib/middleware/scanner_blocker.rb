# Rejects common vulnerability-scanner probes (WordPress, PHP, dotfiles) at the
# front of the Rack stack with a fast 403 — before they reach the router. Bots
# hammer paths like /wp-includes/wlwmanifest.xml, /xmlrpc.php, and /.env; without
# this each one raises ActionController::RoutingError and spams the logs. None of
# these patterns correspond to a real route (this is a Rails app, no PHP/WordPress),
# and .well-known and other legitimate paths are deliberately not matched.
#
# The query string gets its own pattern: WordPress's permalink-less REST form
# puts everything after the "?" (/?rest_route=/wp/v2/users), so the path is a
# bare "/" and would otherwise render the root page for every probe.
#
# Lives in lib/middleware (ignored by autoload) and is required from application.rb,
# because the middleware stack needs the actual class at boot, before Zeitwerk.
class ScannerBlocker
  PROBE = %r{
    wp-(?:includes|admin|content|login|json) | wlwmanifest | xmlrpc |
    /wordpress\b | phpmyadmin | /adminer | \.php(?:\z|[/?]) |
    /\.(?:env|git|aws|ssh|htaccess)\b
  }xi

  QUERY_PROBE = /\brest_route=/i

  # The exception to "this is a Rails app, no PHP": we impersonate Sendy for
  # BookFunnel (Sendy::BaseController and friends), and Sendy's API paths end
  # in .php — so our own routes trip the rule above and 403 before reaching
  # Rails. That is how the integration failed on its first day, and the reason
  # it took a deploy to find is that a refusal here happens at position 0,
  # ahead of Rails' logger: the request left no trace anywhere.
  #
  # So the allowance is Sendy's whole subscriber/list/brand API rather than
  # only the two paths we answer. A call we haven't implemented then 404s
  # visibly in the log instead of vanishing, which is the difference between
  # reading the answer and guessing at it. Campaign paths stay refused — we
  # will never answer those. This is log hygiene, not a security boundary:
  # what these paths actually do is gated by a per-account API key.
  SENDY_API = %r{\A/api/(?:subscribers|lists|brands)/[a-z0-9-]+\.php\z}

  # Headers that only a Next.js client would send. Next-Action names a Server
  # Action to invoke, and what sends it to a Rails app is the React Server
  # Components RCE scanner (late 2025 onwards): a multipart POST to any path.
  # It must be refused *here*, before anything reads the body, because the
  # probe's form parts declare charset=utf-16le and Rack 3.2's multipart
  # parser force-encodes the field *name* to match — then Rack::MethodOverride,
  # which parses every form POST looking for _method and sits ahead of Rails'
  # exception handling, trips over it and the probe 500s (issue #32).
  PROBE_HEADERS = %w[ HTTP_NEXT_ACTION ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) if SENDY_API.match?(env["PATH_INFO"])

    if probe?(env)
      [ 403, { "content-type" => "text/plain" }, [ "Forbidden\n" ] ]
    else
      @app.call(env)
    end
  end

  private
    def probe?(env)
      env["PATH_INFO"].to_s.match?(PROBE) ||
        env["QUERY_STRING"].to_s.match?(QUERY_PROBE) ||
        PROBE_HEADERS.any? { |header| env.key?(header) }
    end
end
