require "test_helper"

class CustomDomainTest < ActiveSupport::TestCase
  test "normalises the hostname through Hostname on create" do
    domain = accounts(:merovex).custom_domains.create!(hostname: "HTTPS://WWW.Example.com/")
    assert_equal "www.example.com", domain.hostname
  end

  test "hostname is globally unique" do
    accounts(:merovex).custom_domains.create!(hostname: "example.com")
    dup = accounts(:merovex).custom_domains.new(hostname: "example.com")
    assert_not dup.valid?
    assert_includes dup.errors[:hostname], "has already been taken"
  end

  test "rejects our namespace on create" do
    domain = accounts(:merovex).custom_domains.new(hostname: "x.kindredquill.com")
    assert_not domain.valid?
  end

  test "provisioned? needs BOTH the hostname and ssl status active" do
    domain = accounts(:merovex).custom_domains.create!(hostname: "example.com", status: "verifying", ssl_status: "active")
    domain.cloudflare_status = "active"
    assert domain.provisioned?

    domain.cloudflare_status = "pending"
    assert_not domain.provisioned?

    domain.cloudflare_status = "active"
    domain.ssl_status = "pending_validation"
    assert_not domain.provisioned?
  end

  test "provisioned? accepts a hostname mid-rotation, not just the literal active" do
    # active_redeploying is a healthy hostname; exact equality would strand it
    # forever, since nothing revisits a row that never flips.
    domain = accounts(:merovex).custom_domains.create!(hostname: "example.com", status: "verifying", ssl_status: "active")
    domain.cloudflare_status = "active_redeploying"

    assert domain.provisioned?
  end

  test "provisioned? still flips a row the poll chain gave up on" do
    # "error" means nothing is watching any more, not that the domain is
    # unsalvageable — the author publishing the record later must still count.
    domain = accounts(:merovex).custom_domains.create!(hostname: "example.com", status: "error", ssl_status: "active")
    domain.cloudflare_status = "active"

    assert domain.provisioned?
  end

  test "validation_records round-trip through the JSON column as value objects" do
    domain = accounts(:merovex).custom_domains.create!(hostname: "example.com",
      validation_records: [ { "txt_name" => "_acme-challenge.example.com", "txt_value" => "one" },
                            { "txt_name" => "_acme-challenge.example.com", "txt_value" => "two" } ])

    records = domain.reload.validation_records
    assert_equal 2, records.size
    assert_equal "_acme-challenge.example.com", records.first.txt_name
    assert_equal %w[ one two ], records.map(&:txt_value)
  end

  test "validation_records defaults to empty rather than nil" do
    assert_empty accounts(:merovex).custom_domains.create!(hostname: "example.com").validation_records
  end
end
