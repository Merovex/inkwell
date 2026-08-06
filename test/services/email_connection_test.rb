require "test_helper"

class EmailConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Records every call so tests can assert the provisioning sequence without
  # touching SES — the email twin of DomainConnectionTest::FakeClient.
  class FakeClient
    attr_reader :tenants, :identity_associations, :config_set_associations,
      :created_identities, :mail_froms, :deleted_identities

    def initialize
      @tenants = []
      @identity_associations = []
      @config_set_associations = []
      @created_identities = []
      @mail_froms = {}
      @deleted_identities = []
    end

    def create_tenant(name) = @tenants << name
    def associate_identity(tenant, domain) = @identity_associations << [ tenant, domain ]
    def associate_config_set(tenant, name) = @config_set_associations << [ tenant, name ]

    def create_identity(domain, config_set: nil)
      @created_identities << [ domain, config_set ]
      %w[ token1 token2 token3 ]
    end

    def set_mail_from(domain, mail_from) = @mail_froms[domain] = mail_from
    def delete_identity(domain) = @deleted_identities << domain
  end

  test "provision_tenant creates the tenant, associates the shared lane, and stamps the account" do
    fake = FakeClient.new
    account = accounts(:merovex)

    result = EmailConnection.provision_tenant(account, client: fake)

    assert result.ok?
    assert_equal [ account.ses_tenant_name ], fake.tenants
    assert_includes fake.identity_associations, [ account.ses_tenant_name, Account.shared_sending_domain ]
    assert account.reload.ses_tenant_provisioned?
  end

  test "provision_tenant keeps the original provisioning stamp on re-run" do
    account = accounts(:merovex)
    account.update!(ses_tenant_provisioned_at: 2.days.ago)
    original = account.ses_tenant_provisioned_at

    EmailConnection.provision_tenant(account, client: FakeClient.new)
    assert_equal original, account.reload.ses_tenant_provisioned_at
  end

  test "provision_tenant catches up an already-connected sending domain" do
    account = accounts(:merovex)
    account.sending_domains.create!(domain: "news.merovex.press", status: "verifying")
    fake = FakeClient.new

    EmailConnection.provision_tenant(account, client: fake)
    assert_includes fake.identity_associations, [ account.ses_tenant_name, "news.merovex.press" ]
  end

  test "connect creates the identity with MAIL FROM and a verifying row, and enqueues the poll" do
    fake = FakeClient.new
    account = accounts(:merovex)
    account.update!(ses_tenant_provisioned_at: Time.current)

    result = nil
    assert_enqueued_with(job: SendingDomainStatusJob) do
      result = EmailConnection.connect(account: account, input: "News.Merovex.Press", client: fake)
    end

    assert result.ok?
    assert_equal [ [ "news.merovex.press", Rails.application.credentials.dig(:ses, :marketing_config_set) ] ],
      fake.created_identities
    assert_equal "bounce.news.merovex.press", fake.mail_froms["news.merovex.press"]
    assert_includes fake.identity_associations, [ account.ses_tenant_name, "news.merovex.press" ]

    domain = account.sending_domains.find_by(domain: "news.merovex.press")
    assert domain.verifying?
    assert_equal %w[ token1 token2 token3 ], domain.dkim_tokens
    assert_equal "bounce.news.merovex.press", domain.mail_from_domain
  end

  test "connect skips the tenant association when the tenant isn't provisioned yet" do
    fake = FakeClient.new
    EmailConnection.connect(account: accounts(:merovex), input: "news.merovex.press", client: fake)
    assert_empty fake.identity_associations
  end

  test "connect refuses a bare apex — subdomain required" do
    result = EmailConnection.connect(account: accounts(:merovex), input: "merovex.press", client: FakeClient.new)
    assert_not result.ok?
    assert_match(/subdomain/, result.error)
    assert_equal 0, accounts(:merovex).sending_domains.count
  end

  test "connect refuses our shared sending domain" do
    result = EmailConnection.connect(account: accounts(:merovex),
      input: "sneaky.#{Account.shared_sending_domain}", client: FakeClient.new)
    assert_not result.ok?
    assert_match(/our domain/, result.error)
  end

  test "connect refuses a domain already connected to another account" do
    other = Account.create_with_owner(name: "Other Press", owner: users(:alice))
    other.sending_domains.create!(domain: "news.taken.example", status: "verifying")

    result = EmailConnection.connect(account: accounts(:merovex), input: "news.taken.example", client: FakeClient.new)
    assert_not result.ok?
    assert_match(/already connected/, result.error)
  end

  test "connect surfaces a bad domain as an error, not an exception" do
    result = EmailConnection.connect(account: accounts(:merovex), input: "not a domain", client: FakeClient.new)
    assert_not result.ok?
    assert result.error.present?
  end

  test "disconnect deletes the identity and marks the row disconnected" do
    fake = FakeClient.new
    domain = accounts(:merovex).sending_domains.create!(domain: "news.merovex.press", status: "live")

    result = EmailConnection.disconnect(sending_domain: domain, client: fake)

    assert result.ok?
    assert_includes fake.deleted_identities, "news.merovex.press"
    assert domain.reload.disconnected?
  end
end
