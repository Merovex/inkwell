# Orchestrates a site's SES email tenancy — the email twin of
# DomainConnection, same shape so the controller stays thin and tests inject a
# fake Ses::Client (docs/email-tenant-byod-plan.md).
#
#   provision_tenant: create the site-<slug> tenant + associate the shared
#     identity and both config sets, so shared-lane sends attribute the moment
#     the tenant exists. Idempotent; callable from console (Tenant Zero is
#     comped) and later by the purchase flow. Stamps ses_tenant_provisioned_at.
#   connect: validate (subdomain required — the apex is refused so the
#     author's root-domain reputation stays isolated) → CreateEmailIdentity
#     (DKIM tokens come back) → MAIL FROM bounce.<domain> → associate the
#     identity with the site's tenant → persist "verifying" → enqueue the poll.
#   disconnect: DeleteEmailIdentity, mark the row disconnected.
class EmailConnection
  Result = Struct.new(:ok, :sending_domain, :error, keyword_init: true) do
    def ok? = ok
  end

  MAIL_FROM_PREFIX = "bounce"

  def self.connect(...) = new(...).connect
  def self.disconnect(...) = new(...).disconnect
  def self.provision_tenant(account, client: Ses::Client.new) = new(account: account, client: client).provision_tenant

  def initialize(account: nil, input: nil, sending_domain: nil, client: Ses::Client.new)
    @account = account || sending_domain&.account
    @client = client
    @input = input
    @sending_domain = sending_domain
  end

  def provision_tenant
    tenant = @account.ses_tenant_name
    @client.create_tenant(tenant)
    @client.associate_identity(tenant, Account.shared_sending_domain)
    # Sends that name a tenant AND a config set need both associated — site
    # mail rides the marketing set (broadcasts, drips) and the transactional
    # set (subscriber confirmations), so associate the pair.
    [ marketing_config_set, transactional_config_set ].compact.each do |config_set|
      @client.associate_config_set(tenant, config_set)
    end
    # Adopted BYOD identities connected before the tenant existed catch up here.
    @account.sending_domains.connected.each { |domain| @client.associate_identity(tenant, domain.domain) }
    @account.update!(ses_tenant_provisioned_at: Time.current) unless @account.ses_tenant_provisioned?
    Result.new(ok: true)
  rescue Ses::Client::Error => error
    failure(error.message)
  end

  def connect
    parsed = Hostname.new(@input)
    return failure(parsed.error) unless parsed.valid?
    hostname = parsed.normalized
    return failure("Connect a subdomain like news.#{hostname} — sending from the bare domain would tie your root domain's email reputation to the newsletter") unless subdomain?(hostname)
    return failure("That's our domain — connect a subdomain of a domain you own") if ours?(hostname)
    return failure("#{hostname} is already connected to another site") if claimed_elsewhere?(hostname)
    # One sending domain per site. Reconnecting the SAME domain stays allowed —
    # that's the retry/adopt path; a different one needs a disconnect first.
    if (current = @account.sending_domains.connected.where.not(domain: hostname).first)
      return failure("Disconnect #{current.domain} first — a site sends from one domain")
    end

    tokens = @client.create_identity(hostname, config_set: marketing_config_set)
    mail_from = "#{MAIL_FROM_PREFIX}.#{hostname}"
    @client.set_mail_from(hostname, mail_from)
    @client.associate_identity(@account.ses_tenant_name, hostname) if @account.ses_tenant_provisioned?

    domain = @account.sending_domains.find_or_initialize_by(domain: hostname)
    domain.update!(status: "verifying", dkim_tokens: tokens, mail_from_domain: mail_from,
      last_checked_at: Time.current)
    SendingDomainStatusJob.set(wait: 30.seconds).perform_later(@account)
    Result.new(ok: true, sending_domain: domain)
  rescue Ses::Client::Error => error
    failure(error.message)
  end

  def disconnect
    @client.delete_identity(@sending_domain.domain)
    @sending_domain.update!(status: "disconnected")
    Result.new(ok: true, sending_domain: @sending_domain)
  rescue Ses::Client::Error => error
    failure(error.message)
  end

  private
    # Subdomain-required, by label count. Heuristic: a multi-part public
    # suffix (news.example.co.uk's apex has three labels) slips past, but
    # Hostname already rejects the pathological shapes and SES verification
    # still gates actual sending.
    def subdomain?(hostname) = hostname.split(".").length >= 3

    # Hostname refuses the kindredquill.com namespace; the shared sending
    # domain is a different registrable domain, so refuse it here.
    def ours?(hostname)
      shared = Account.shared_sending_domain
      hostname == shared || hostname.end_with?(".#{shared}")
    end

    def claimed_elsewhere?(hostname)
      SendingDomain.connected.where(domain: hostname).where.not(account_id: @account.id).exists?
    end

    def marketing_config_set = Rails.application.credentials.dig(:ses, :marketing_config_set)
    def transactional_config_set = Rails.application.credentials.dig(:ses, :transactional_config_set)

    def failure(message) = Result.new(ok: false, error: message)
end
