# The account's own Turnstile widget — the front-door twin of
# EmailConnection.provision_tenant: one managed-mode widget per account, keys
# stamped on the account row so the export contract and siteverify read
# per-account values (widget sharding is data entry, never a schema change).
#
#   provision: create the widget covering every host the account's signup
#     form can render on — its custom-domain apexes plus the platform apex
#     (a Turnstile hostname covers its subdomains, so the apex entry also
#     covers www. and sites.). Idempotent; callable from console for an
#     already-connected site (Tenant Zero) and by DomainConnection when a
#     custom domain connects.
#   register_hostname / deregister_hostname: keep the widget's hostname list
#     in sync as domains connect and disconnect.
class TurnstileConnection
  def self.provision(account, client: Cloudflare::Client.new) = new(account: account, client: client).provision

  def initialize(account:, client: Cloudflare::Client.new)
    @account = account
    @client = client
  end

  def provision
    return if @account.turnstile_site_key.present?

    widget = @client.create_turnstile_widget(name: "site-#{@account.slug}", domains: initial_domains)
    @account.update!(turnstile_site_key: widget.sitekey, turnstile_secret_key: widget.secret)
  end

  def register_hostname(hostname)
    provision
    @client.add_turnstile_domain(@account.turnstile_site_key, hostname)
  end

  def deregister_hostname(hostname)
    return if @account.turnstile_site_key.blank?

    @client.remove_turnstile_domain(@account.turnstile_site_key, hostname)
  end

  private
    # Verifying rows count too: a connect in flight lands within moments, and
    # a stale entry on the widget is harmless — the allowlist only OPENS
    # hostnames, it can't break others.
    def initial_domains
      apexes = @account.custom_domains.map { |domain| domain.hostname.delete_prefix("www.") }
      (platform_hosts + apexes).uniq
    end

    # The sites host serves every domain-less account's newsletter form; only
    # under host enforcement, like the rest of the multi-host posture.
    def platform_hosts
      AccountHost.enforced? ? [ AccountHost.sites_host ] : []
    end
end
