require "test_helper"

class DomainConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Records every call so tests can assert the KV-before-DNS ordering and the
  # disconnect teardown without touching the real Cloudflare API.
  class FakeClient
    attr_reader :kv, :created, :deleted_hostnames, :deleted_kv

    def initialize
      @kv = {}
      @created = []
      @deleted_hostnames = []
      @deleted_kv = []
    end

    def create_custom_hostname(hostname)
      @created << hostname
      Cloudflare::CustomHostname.new(
        "id" => "id-#{hostname}", "hostname" => hostname, "status" => "pending",
        "ssl" => { "status" => "pending_validation",
                   "validation_records" => [ { "txt_name" => "_cf-custom-hostname.#{hostname}",
                                               "txt_value" => "tv-#{hostname}" } ] }
      )
    end

    def kv_put(hostname, slug) = @kv[hostname] = slug
    def kv_delete(hostname) = (@deleted_kv << hostname) && @kv.delete(hostname)
    def delete_custom_hostname(id) = @deleted_hostnames << id
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
    assert_equal "_cf-custom-hostname.www.merovex.press", rows.find(&:canonical?).txt_name
  end

  test "connect refuses a hostname already connected to another account" do
    other = Account.create_with_owner(name: "Other Press", owner: users(:alice))
    other.custom_domains.create!(hostname: "taken.example", status: "verifying")

    result = DomainConnection.connect(account: accounts(:merovex), input: "taken.example", client: FakeClient.new)
    assert_not result.ok?
    assert_match(/already connected/, result.error)
    assert_equal 0, accounts(:merovex).custom_domains.count
  end

  test "connect surfaces a bad domain as an error, not an exception" do
    result = DomainConnection.connect(account: accounts(:merovex), input: "not a domain", client: FakeClient.new)
    assert_not result.ok?
    assert result.error.present?
  end

  test "disconnect deletes the KV key and the custom hostname" do
    fake = FakeClient.new
    DomainConnection.connect(account: accounts(:merovex), input: "merovex.press", client: fake)
    domain = accounts(:merovex).custom_domains.find_by(hostname: "www.merovex.press")

    DomainConnection.disconnect(domain: domain, client: fake)

    assert_includes fake.deleted_kv, "www.merovex.press"
    assert_includes fake.deleted_hostnames, domain.cloudflare_id
    assert domain.reload.disconnected?
  end
end
