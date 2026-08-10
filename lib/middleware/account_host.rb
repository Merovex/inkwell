# Host-role routing (ADR 0018), adapted from Fizzy's AccountSlug::Extractor.
#
# Two kinds of hostname once APP_HOST is set:
#   app host     — kindredquill.com/{SLUG}/admin/…: admin + auth for every
#                  account. The slug prefix moves into SCRIPT_NAME, so routes
#                  never namespace it and every URL helper emits it for free.
#   tenant host  — merovex.press: that account's public site, resolved by
#                  accounts.domain (www. folds into the apex). No admin here.
#
# With APP_HOST unset the middleware is a pass-through and routing behaves
# exactly as the single-tenant app always has — which is what makes the
# cut-over a config change (and the rollback an un-set), never a deploy.
module AccountHost
  def self.app_host
    Rails.configuration.x.app_host.presence
  end

  def self.enforced? = !app_host.nil?

  def self.app_host?(request) = request.host == app_host

  # The app host's registrable domain (app.kindredquill.com → kindredquill.com):
  # not a tenant, so strays there bounce to the app host. Nil when the app host
  # has no subdomain to strip.
  def self.apex_host
    app_host.split(".", 2).last if app_host && app_host.count(".") >= 2
  end

  # merovex.press and www.merovex.press are the same tenant.
  def self.canonical_host(host) = host.to_s.downcase.delete_prefix("www.")

  # URL options for a link on the account's PUBLIC site (reader-facing: the
  # blog permalink, newsletter confirm/unsubscribe): the custom domain when
  # connected, else the apex slug path — mirrors Account#public_address. The
  # explicit script_name matters both ways: it must carry the slug on the apex
  # and must clear the admin's mounted /{SLUG} prefix on a custom domain.
  # Without either (legacy single-tenant, dev/test) this returns {} and links
  # fall back to the request/default host — the old behavior.
  def self.public_url_options(account)
    if account&.domain.present?
      { host: account.domain, protocol: "https", script_name: "" }
    elsif account && apex_host
      { host: apex_host, script_name: "/#{account.slug}", protocol: "https" }
    else
      {}
    end
  end

  class Extractor
    # One path segment shaped like a slug (length must match
    # Sluggable::SLUG_LENGTH; literal because this file loads before Zeitwerk).
    SLUG_PREFIX = %r{\A/([0-9A-Za-z]{6})(?=/|\z)}

    def initialize(app)
      @app = app
    end

    def call(env)
      unless AccountHost.enforced?
        # Single-tenant legacy mode pins the first account (the plan's 1.3
        # "constant resolution") so controllers rely on Current.account
        # uniformly whether or not host-role enforcement is on.
        return Current.with_account(Account.first) { @app.call(env) }
      end

      request = ActionDispatch::Request.new(env)

      if AccountHost.app_host?(request)
        call_with_slug_account(request, env)
      # The apex (kindredquill.com) is no longer served by the app — it points
      # at the static marketing site, and a domain-less account's public site
      # lives on sites.kindredquill.com/<handle> (edge-served, Phase 2). The
      # apex-public path is retired (commented below):
      #   elsif AccountHost.canonical_host(request.host) == AccountHost.apex_host
      #     call_with_apex_public(request, env)
      else
        call_with_tenant_account(request, env)
      end
    end

    private
      # RETIRED (Phase 2): the apex no longer serves domain-less accounts' public
      # sites — the apex points at the static marketing site, and a domain-less
      # account's public site is edge-served at sites.kindredquill.com/<handle>.
      # Kept commented for reference / rollback.
      #
      # def call_with_apex_public(request, env)
      #   if (match = SLUG_PREFIX.match(request.path_info)) &&
      #      (account = Account.find_by(slug: Sluggable.normalize(match[1])))
      #     return redirect_to_domain(request, account, match) if account.domain.present?
      #
      #     env["account_host.tenant_account"] = account
      #     mount_at_prefix(request, account, match)
      #     Current.with_account(account) { @app.call(env) }
      #   else
      #     redirect_to_app_host(request)
      #   end
      # end
      #
      # def redirect_to_domain(request, account, match)
      #   rest = match.post_match
      #   rest = "/" if rest.empty?
      #   query = request.query_string.presence
      #   moved_permanently "#{request.scheme}://#{account.domain}#{rest}#{"?#{query}" if query}"
      # end
      #
      # # kindredquill.com itself isn't a tenant — send visitors to the app host.
      # def redirect_to_app_host(request)
      #   moved_permanently "#{request.scheme}://#{AccountHost.app_host}#{request.fullpath}"
      # end
      #
      # def moved_permanently(location)
      #   [ 301, { "location" => location, "content-type" => "text/html" }, [] ]
      # end

      # A prefix only counts when the account actually exists — shape alone
      # can't be trusted ("assets" is a plausible six-char slug, which is also
      # why Sluggable refuses to generate reserved words). Unprefixed paths on
      # the app host (sign-in, setup, /assets, /up) pass through account-less.
      def call_with_slug_account(request, env)
        if (match = SLUG_PREFIX.match(request.path_info)) &&
           (account = Account.find_by(slug: Sluggable.normalize(match[1])))
          env["account_host.slug_account"] = account
          mount_at_prefix(request, account, match)
          Current.with_account(account) { @app.call(env) }
        else
          Current.without_account { @app.call(env) }
        end
      end

      # Any other hostname is a tenant's public site. Development keeps
      # working on bare localhost/127.0.0.1 by falling back to the first
      # account, so the public site stays reachable next to APP_HOST=localhost.
      def call_with_tenant_account(request, env)
        account = Account.find_by(domain: AccountHost.canonical_host(request.host))
        account ||= Account.first if Rails.env.development?

        if account
          env["account_host.tenant_account"] = account
          Current.with_account(account) { @app.call(env) }
        else
          Current.without_account { @app.call(env) }
        end
      end

      # The Fizzy trick: the prefix leaves PATH_INFO for SCRIPT_NAME, so the
      # router never sees it and url_for echoes it back on every generated
      # URL. Mounted under the canonical slug, however the prefix was typed.
      def mount_at_prefix(request, account, match)
        request.engine_script_name = request.script_name = "#{request.script_name}/#{account.slug}"
        rest = match.post_match
        request.path_info = rest.empty? ? "/" : rest
      end
  end
end
