require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Prepare the ingress controller used to receive mail
  # config.action_mailbox.ingress = :relay

  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  # The CORS header is for the island pages below: cross-origin CSS loads
  # fine, but the @font-face files those sheets reference do not without it.
  config.public_file_server.headers = {
    "cache-control" => "public, max-age=#{1.year.to_i}",
    "access-control-allow-origin" => "*"
  }

  # Rails-rendered island pages (newsletter confirm/sent/…) are served on
  # TENANT hosts through the edge Worker, whose /assets/* belongs to the
  # static site build in R2 — a relative asset path 404s there and the page
  # renders naked. Absolute asset URLs against the app host keep Rails pages
  # dressed wherever they're proxied. No-op until APP_HOST is set.
  config.asset_host = ENV["APP_HOST"].presence && "https://#{ENV["APP_HOST"]}"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates. This is the Rails
  # app's host (merovex.press) — where confirm/unsubscribe/view-on-web routes
  # resolve — not the sending subdomains.
  config.action_mailer.default_url_options = { host: Rails.application.credentials.dig(:ses, :host) || "example.com" }

  # SES is the DEFAULT pipe for everything (docs/email-architecture.md,
  # 2026-08-05): one account carries the platform (Quill) and Merovex Press
  # interim; the verify.* stream moves to its own AWS account when created.
  # Transactional signs d=auth.merovex.press, bulk signs d=news.merovex.press —
  # separate domain reputations inside the shared account.
  config.action_mailer.delivery_method = :ses_v2
  # Postmark stays configured as the dormant warm-standby (the provider flip
  # is the recovery path if SES throttles or the shared pool sours); the
  # account itself is scheduled for cancellation once the SES cutover proves
  # out — re-entry trigger recorded in docs/email-architecture.md.
  config.action_mailer.postmark_settings = {
    api_token: Rails.application.credentials.postmark_api_token
  }

  # SES (API v2) carries the bulk — broadcasts and drip steps — for volume
  # economics; both mailers already stamp the marketing config set + message
  # tags via delivery_method_options (ADR 0015). Ops preconditions for this
  # pipe: SES account-level auto-suppression OFF (our database is the
  # authoritative suppression list — with it on, AWS silently drops sends and
  # Subscriber.status drifts, ADR 0025), the SNS subscription to /webhooks/ses
  # confirmed, and the news.merovex.press identity verified.
  config.action_mailer.ses_v2_settings = {
    region: Rails.application.credentials.dig(:ses, :region),
    access_key_id: Rails.application.credentials.dig(:ses, :access_key_id),
    secret_access_key: Rails.application.credentials.dig(:ses, :secret_access_key)
  }

  # Inbound: SES receipt rule → S3 (kindredquill-inbound-email) → SNS → the
  # :ses ingress → SupportMailbox → Missives. Activated by the mail-in SNS
  # topic ARN (rake email:provision_inbound prints it). NOTE:
  # aws-actionmailbox-ses takes the SINGULAR `subscribed_topic` (one ARN).
  if (topic = Rails.application.credentials.dig(:mailin, :sns_topic_arn)).present?
    config.action_mailbox.ingress = :ses
    config.action_mailbox.ses.subscribed_topic = topic

    # The SNS notification only points at bucket/key; the gem reads the raw
    # message back out of S3 with these credentials — the inkwell-ses IAM user
    # also needs s3:GetObject on the inbound bucket.
    config.action_mailbox.ses.s3_client_options = {
      region: Rails.application.credentials.dig(:ses, :region),
      access_key_id: Rails.application.credentials.dig(:ses, :access_key_id),
      secret_access_key: Rails.application.credentials.dig(:ses, :secret_access_key)
    }
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
