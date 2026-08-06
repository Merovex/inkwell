# Orchestrates connecting (and disconnecting) a custom domain — the sequence
# the runbook lays out, in one place so the controller stays thin and tests can
# inject a fake Cloudflare client.
#
#   connect: normalise → uniqueness gate → for each hostname (apex + www):
#     create the custom hostname, THEN write KV (so the Worker is ready the
#     instant DNS arrives), THEN persist the row → enqueue the status poll.
#   disconnect: delete the KV key AND the custom hostname (both, or the
#     hostname keeps eating the 100-hostname allowance and keeps resolving).
class DomainConnection
  Result = Struct.new(:ok, :domains, :error, keyword_init: true) do
    def ok? = ok
  end

  def self.connect(...) = new(...).connect
  def self.disconnect(...) = new(...).disconnect

  def initialize(account: nil, input: nil, domain: nil, client: Cloudflare::Client.new)
    @account = account || domain&.account
    @input = input
    @domain = domain
    @client = client
  end

  def connect
    parsed = Hostname.new(@input)
    return failure(parsed.error) unless parsed.valid?

    hostnames = parsed.onboarding_set
    if (taken = hostnames.find { |h| claimed_elsewhere?(h) })
      return failure("#{taken} is already connected to another site")
    end

    domains = hostnames.map { |hostname| provision(hostname, canonical: hostname == parsed.canonical) }
    CustomDomainStatusJob.set(wait: 30.seconds).perform_later(@account)
    Result.new(ok: true, domains: domains)
  rescue Cloudflare::Client::Error => error
    failure(error.message)
  end

  def disconnect
    @client.kv_delete(@domain.hostname)
    @client.delete_custom_hostname(@domain.cloudflare_id) if @domain.cloudflare_id.present?
    @domain.update!(status: "disconnected")
    # Un-bridge the legacy account.domain the go-live stamped, so builds fall
    # back to the slug-path baseURL (the clear itself schedules the rebuild).
    @account.update!(domain: nil) if @account.domain == @domain.hostname.delete_prefix("www.")
    Result.new(ok: true, domains: [ @domain ])
  rescue Cloudflare::Client::Error => error
    failure(error.message)
  end

  private
    # Step 2 then 3 then 1's persistence: create the hostname, ready KV before
    # any DNS is announced, then record what we got back for the poll + the
    # author's DNS instructions. Reuses this account's existing row on retry.
    def provision(hostname, canonical:)
      created = @client.create_custom_hostname(hostname)
      @client.kv_put(hostname, @account.slug)

      domain = @account.custom_domains.find_or_initialize_by(hostname: hostname)
      domain.update!(
        canonical: canonical, status: "verifying",
        cloudflare_id: created.id, ssl_status: created.ssl_status,
        txt_name: created.txt_name, txt_value: created.txt_value,
        last_checked_at: Time.current
      )
      domain
    end

    def claimed_elsewhere?(hostname)
      CustomDomain.connected.where(hostname: hostname).where.not(account_id: @account.id).exists?
    end

    def failure(message) = Result.new(ok: false, error: message)
end
