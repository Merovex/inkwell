require "test_helper"

class DomainConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Records every call so tests can assert the KV-before-DNS ordering and the
  # disconnect teardown without touching the real Cloudflare API.
  class FakeClient
    attr_reader :kv, :created, :deleted_hostnames, :deleted_kv, :widgets

    def initialize
      @kv = {}
      @created = []
      @deleted_hostnames = []
      @deleted_kv = []
      @widgets = {}
    end

    def create_custom_hostname(hostname)
      @created << hostname
      Cloudflare::CustomHostname.new(
        "id" => "id-#{hostname}", "hostname" => hostname, "status" => "pending",
        "ssl" => { "status" => "pending_validation",
                   "validation_records" => [ { "txt_name" => "_acme-challenge.#{hostname}",
                                               "txt_value" => "tv-#{hostname}" } ] }
      )
    end

    def kv_put(hostname, slug) = @kv[hostname] = slug
    def kv_delete(hostname) = (@deleted_kv << hostname) && @kv.delete(hostname)
    def delete_custom_hostname(id) = @deleted_hostnames << id

    def create_turnstile_widget(name:, domains:)
      sitekey = "sk-#{name}"
      @widgets[sitekey] = domains.dup
      Cloudflare::TurnstileWidget.new("sitekey" => sitekey, "secret" => "secret-#{name}", "domains" => domains)
    end

    def add_turnstile_domain(sitekey, hostname)
      @widgets.fetch(sitekey) << hostname unless @widgets.fetch(sitekey).include?(hostname)
    end

    def remove_turnstile_domain(sitekey, hostname) = @widgets.fetch(sitekey).delete(hostname)
  end

  # The widget calls ride the same client seam and error path as the
  # hostname + KV calls — one bad call fails the whole connect (hard gate).
  class BrokenTurnstileClient < FakeClient
    def create_turnstile_widget(**) = raise(Cloudflare::Client::Error, "turnstile says no")
  end

  test "connect provisions apex + www, writes KV, and creates verifying rows" do
    fake = FakeClient.new
    result = nil
    assert_enqueued_with(job: CustomDomainStatusJob) do
      result = DomainConnection.connect(account: accounts(:merovex), input: "merovex.press", client: fake)
    end

    assert result.ok?
    assert_equal %w[merovex.press www.merovex.press], fake.created.sort
    assert_equal accounts(:merovex).slug, fake.kv["merovex.press"]
    assert_equal accounts(:merovex).slug, fake.kv["www.merovex.press"]

    rows = accounts(:merovex).custom_domains.order(:hostname)
    assert_equal %w[merovex.press www.merovex.press], rows.map(&:hostname)
    assert rows.all?(&:verifying?)
    assert_equal "www.merovex.press", rows.find(&:canonical?).hostname
    canonical = rows.find(&:canonical?)
    assert_equal "_acme-challenge.www.merovex.press", canonical.validation_records.sole.txt_name
    assert_equal "tv-www.merovex.press", canonical.validation_records.sole.txt_value
  end

  test "connect refuses a hostname already connected to another account" do
    other = Account.create_with_owner(name: "Other Press", owner: users(:alice))
    other.custom_domains.create!(hostname: "taken.example", status: "verifying")

    result = DomainConnection.connect(account: accounts(:merovex), input: "taken.example", client: FakeClient.new)
    assert_not result.ok?
    assert_match(/already connected/, result.error)
    assert_equal 0, accounts(:merovex).custom_domains.count
  end

  test "connect refuses a second domain while one is connected" do
    fake = FakeClient.new
    DomainConnection.connect(account: accounts(:merovex), input: "merovex.press", client: fake)

    result = DomainConnection.connect(account: accounts(:merovex), input: "other.example", client: fake)
    assert_not result.ok?
    assert_match(/Disconnect merovex\.press first/, result.error)

    # Reconnecting the SAME apex reuses its rows — the retry path.
    assert DomainConnection.connect(account: accounts(:merovex), input: "merovex.press", client: fake).ok?
  end

  test "connect surfaces a bad domain as an error, not an exception" do
    result = DomainConnection.connect(account: accounts(:merovex), input: "not a domain", client: FakeClient.new)
    assert_not result.ok?
    assert result.error.present?
  end

  test "connect provisions the account's Turnstile widget and registers the apex" do
    fake = FakeClient.new
    DomainConnection.connect(account: accounts(:merovex), input: "merovex.press", client: fake)

    account = accounts(:merovex).reload
    assert account.turnstile_site_key.present?, "widget keys stamped on the account"
    assert account.turnstile_secret_key.present?
    assert_includes fake.widgets.fetch(account.turnstile_site_key), "merovex.press"
    assert_not_includes fake.widgets.fetch(account.turnstile_site_key), "www.merovex.press",
      "the apex entry covers www — no slot wasted"
  end

  test "connect reuses the account's existing widget for a later domain" do
    fake = FakeClient.new
    accounts(:merovex).update!(turnstile_site_key: "sk-existing", turnstile_secret_key: "s3cret")
    fake.widgets["sk-existing"] = [ "old.example" ]

    DomainConnection.connect(account: accounts(:merovex), input: "merovex.press", client: fake)

    assert_equal "sk-existing", accounts(:merovex).reload.turnstile_site_key
    assert_equal %w[old.example merovex.press], fake.widgets["sk-existing"]
  end

  test "a failed Turnstile registration fails the connect — hard gate" do
    result = DomainConnection.connect(account: accounts(:merovex), input: "merovex.press", client: BrokenTurnstileClient.new)

    assert_not result.ok?
    assert_match(/turnstile says no/, result.error)
    # The hostname + KV work persists; reconnecting the same apex is the
    # documented retry path and reuses those rows.
    assert accounts(:merovex).custom_domains.exists?(hostname: "merovex.press")
  end

  test "disconnect deletes the KV key and the custom hostname" do
    fake = FakeClient.new
    DomainConnection.connect(account: accounts(:merovex), input: "merovex.press", client: fake)
    domain = accounts(:merovex).custom_domains.find_by(hostname: "www.merovex.press")

    DomainConnection.disconnect(domain: domain, client: fake)

    assert_includes fake.deleted_kv, "www.merovex.press"
    assert_includes fake.deleted_hostnames, domain.cloudflare_id
    assert domain.reload.disconnected?
    assert_not_includes fake.widgets.fetch(accounts(:merovex).reload.turnstile_site_key), "merovex.press",
      "the apex frees its widget slot"
  end

  test "disconnect un-bridges account.domain and reschedules the build" do
    fake = FakeClient.new
    DomainConnection.connect(account: accounts(:merovex), input: "merovex.press", client: fake)
    accounts(:merovex).update!(domain: "merovex.press") # the go-live stamp
    domain = accounts(:merovex).custom_domains.find_by(hostname: "merovex.press")

    assert_enqueued_with(job: SiteBuildJob, args: [ accounts(:merovex) ]) do
      DomainConnection.disconnect(domain: domain, client: fake)
    end
    assert_nil accounts(:merovex).reload.domain
  end
end
