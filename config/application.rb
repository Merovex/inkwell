require_relative "boot"

require "rails/all"

# Rack middleware inserted into the stack below — required here (not autoloaded)
# because the stack needs the class at boot, before Zeitwerk is set up.
require_relative "../lib/middleware/scanner_blocker"

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

    # Magic-link registration policy:
    #   :invite_only — only existing users may sign in; new accounts are added
    #                  out-of-band. (The first user ever is created via the Setup
    #                  flow, which runs only when no users exist — see SetupsController.)
    #   :open        — anyone may self-register via the Signup flow.
    config.x.authentication.registration_policy = :invite_only

    # Turn the weekly newsletter sunset sweep on only once Mailgun open/click
    # tracking is live — otherwise everyone looks cold (ADR 0014).
    config.x.newsletter.sunset_enabled = ENV["NEWSLETTER_SUNSET"] == "true"

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
  end
end
