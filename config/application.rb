require_relative "boot"

require "rails/all"

# Rack middleware inserted into the stack below — required here (not autoloaded)
# because the stack needs the class at boot, before Zeitwerk is set up.
require_relative "../lib/middleware/scanner_blocker"
require_relative "../lib/middleware/account_host"
require_relative "../lib/middleware/island_host"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Inkwell
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks middleware])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Wall-clock times entered in the UI (e.g. a pulse's "ask at 2:00 PM",
    # stored as bare minutes-past-midnight) are interpreted in this zone by the
    # schedulers (PulseTickJob's Time.zone.now). Storage stays UTC. If circles
    # ever span operators in other zones, this becomes a per-circle setting.
    config.time_zone = "Eastern Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Who may hand out join codes (Signup's gate). false = only root users
    # hold a code; flip to true for open beta, where every user may invite
    # (their code appears in personal settings). Hard-coded on purpose.
    config.x.join_codes.open = false

    # The app host: admin + auth for every account, path-prefixed by account
    # slug (kindredquill.com/K7TXM4/admin). When set, host-role routing is
    # enforced and tenant domains serve only their public site. Unset =
    # single-tenant legacy behavior, so a deploy without APP_HOST can never
    # lock the admin out (ADR 0018).
    config.x.app_host = ENV["APP_HOST"]

    # The Solid Queue dashboard rides the app's own authentication instead of
    # its default HTTP basic auth: sign-in via ApplicationController, root-only
    # via Admin::JobsBaseController. Mounted at /jobs on the app host (routes).
    config.mission_control.jobs.base_controller_class = "Admin::JobsBaseController"
    config.mission_control.jobs.http_basic_auth_enabled = false

    # Turn the weekly newsletter sunset sweep on only once SES open/click
    # tracking is live — otherwise everyone looks cold (ADR 0014).
    config.x.newsletter.sunset_enabled = ENV["NEWSLETTER_SUNSET"] == "true"

    # Cloudflare for SaaS: the kindredquill.com zone, the account, the HOSTNAMES
    # KV namespace, and the CNAME target authors point their www at. These IDs
    # are not secret (ENV-overridable, with the provisioned values as defaults);
    # the API token IS secret and lives in credentials (cloudflare.api_token).
    config.x.cloudflare.zone_id = ENV.fetch("CF_ZONE_ID", "1eb37a3d7c529846411c5030707a0d5f")
    config.x.cloudflare.account_id = ENV.fetch("CF_ACCOUNT_ID", "a65cb156b161e9bcd5107601fcc6255a")
    config.x.cloudflare.kv_namespace_id = ENV.fetch("CF_KV_NAMESPACE_ID", "31cc38518280423694f78a0ae0726878")
    config.x.cloudflare.cname_target = ENV.fetch("CF_CNAME_TARGET", "sites.kindredquill.com")

    # Mail rendered by deliver_later must carry the enqueuing request's
    # account, like every other job (see ApplicationMailDeliveryJob).
    config.action_mailer.delivery_job = "ApplicationMailDeliveryJob"

    # Deliver through Postmark. The SES wiring in production.rb is being
    # plumbed around, not removed — but note environments load after this
    # file, so production.rb's delivery_method assignment wins until it is
    # switched over.
    config.action_mailer.delivery_method = :postmark
    config.action_mailer.postmark_settings = {
      api_token: Rails.application.credentials.postmark_api_token
    }

    # Use libvips — it's what the Dockerfile installs (and the Rails 8 default).
    # ImageMagick is NOT in the image, so :mini_magick fails to generate any
    # variant in production, which breaks every image (all render via variants).
    config.active_storage.variant_processor = :vips

    # Serve attachments through the app (proxy) rather than a 302 redirect to the
    # storage service. With the Disk service Rails serves the bytes either way, so
    # proxy just removes the extra round-trip — and it sends long-lived, immutable
    # cache headers, making the images CDN-cacheable if one is ever added.
    config.active_storage.resolve_model_to_route = :rails_storage_proxy

    # Refuse vulnerability-scanner probes (/wp-…, /xmlrpc.php, /.env, …) at the
    # very front of the Rack stack, before routing, so they don't spam the logs
    # with RoutingError noise. (Required above; passed as a class, not a string.)
    config.middleware.insert_before 0, ScannerBlocker

    # Resolve the request's account last in the stack, right before routing:
    # slug prefix on the app host, domain lookup on tenant hosts (ADR 0018).
    config.middleware.insert_after Rack::TempfileReaper, AccountHost::Extractor

    # Just before it, restore the tenant host on Worker-proxied island
    # requests (X-Island-Host, gated on the island-auth secret) — the proxy
    # hops in front of Rails rewrite X-Forwarded-Host, which would otherwise
    # route islands to the app host and 404 them.
    config.middleware.insert_before AccountHost::Extractor, IslandHost::Rewriter
  end
end
