require_relative "boot"

require "rails/all"

# Rack middleware inserted into the stack below — required here (not autoloaded)
# because the stack needs the class at boot, before Zeitwerk is set up.
require_relative "../lib/middleware/scanner_blocker"
require_relative "../lib/middleware/account_host"

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
    # config.time_zone = "Central Time (US & Canada)"
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

    # Turn the weekly newsletter sunset sweep on only once SES open/click
    # tracking is live — otherwise everyone looks cold (ADR 0014).
    config.x.newsletter.sunset_enabled = ENV["NEWSLETTER_SUNSET"] == "true"

    # Mail rendered by deliver_later must carry the enqueuing request's
    # account, like every other job (see ApplicationMailDeliveryJob).
    config.action_mailer.delivery_job = "ApplicationMailDeliveryJob"

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
  end
end
