require "test_helper"

# Per-account Turnstile widget provisioning — including the after-the-fact
# console path for a site whose domain connected before widgets existed
# (Tenant Zero).
class TurnstileConnectionTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :widgets

    def initialize = @widgets = {}

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

  test "provision creates the widget over the existing domains and stamps the keys — the Tenant Zero backfill" do
    account = accounts(:merovex)
    account.custom_domains.create!(hostname: "merovex.press", status: "live", canonical: false)
    account.custom_domains.create!(hostname: "www.merovex.press", status: "live", canonical: true)
    fake = FakeClient.new

    TurnstileConnection.provision(account, client: fake)

    account.reload
    assert_equal "sk-site-#{account.slug}", account.turnstile_site_key
    assert_equal "secret-site-#{account.slug}", account.turnstile_secret_key
    assert_equal [ "merovex.press" ], fake.widgets[account.turnstile_site_key],
      "one apex entry covers www; no APP_HOST in test, so no platform sites host"
  end

  test "under host enforcement the widget also allows the platform sites host" do
    Rails.configuration.x.app_host = "app.kindredquill.example"
    account = accounts(:merovex)
    fake = FakeClient.new

    TurnstileConnection.provision(account, client: fake)

    assert_includes fake.widgets[account.reload.turnstile_site_key], AccountHost.sites_host,
      "the domain-less newsletter form is served from the sites host"
  ensure
    Rails.configuration.x.app_host = nil
  end

  test "provision is idempotent — an account with keys is left alone" do
    account = accounts(:merovex)
    account.update!(turnstile_site_key: "sk-existing", turnstile_secret_key: "s3cret")
    fake = FakeClient.new

    TurnstileConnection.provision(account, client: fake)

    assert_equal "sk-existing", account.reload.turnstile_site_key
    assert_empty fake.widgets, "no second widget created"
  end

  test "deregister is a no-op for an account with no widget" do
    assert_nothing_raised do
      TurnstileConnection.new(account: accounts(:merovex), client: FakeClient.new)
        .deregister_hostname("merovex.press")
    end
  end
end
