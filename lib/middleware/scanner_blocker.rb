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

  def initialize(app)
    @app = app
  end

  def call(env)
    if env["PATH_INFO"].to_s.match?(PROBE) || env["QUERY_STRING"].to_s.match?(QUERY_PROBE)
      [ 403, { "content-type" => "text/plain" }, [ "Forbidden\n" ] ]
    else
      @app.call(env)
    end
  end
end
