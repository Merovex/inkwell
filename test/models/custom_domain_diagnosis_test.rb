require "test_helper"

class CustomDomainDiagnosisTest < ActiveSupport::TestCase
  TARGET = "sites.kindredquill.com"
  TARGET_IPS = %w[ 104.21.38.165 172.67.136.119 ].freeze

  # Answers from a canned zone instead of the network: { "name" => { cname:,
  # a:, txt: } }. Anything unlisted resolves to nothing, which is how DNS
  # reports a missing record.
  class FakeResolver
    TYPES = { Resolv::DNS::Resource::IN::CNAME => :cname,
              Resolv::DNS::Resource::IN::A => :a,
              Resolv::DNS::Resource::IN::TXT => :txt }.freeze
    Cname = Struct.new(:name)
    Address = Struct.new(:address)
    Text = Struct.new(:strings)

    def initialize(zone) = @zone = zone

    def getresources(name, type)
      kind = TYPES.fetch(type)
      values = Array(@zone.dig(name, kind))
      case kind
      when :cname then values.map { |v| Cname.new(v) }
      when :a then values.map { |v| Address.new(v) }
      when :txt then values.map { |v| Text.new([ v ]) }
      end
    end
  end

  # Raises the way a dead resolver does, on every question.
  class DeadResolver
    def getresources(*) = raise(Resolv::ResolvError, "no nameservers")
  end

  test "a www CNAME pointing at the target with a matching TXT is just waiting on Cloudflare" do
    assert_equal :pending, diagnose(www,
      "www.merovex.press" => { cname: TARGET },
      "_acme-challenge.www.merovex.press" => { txt: "tv" })
  end

  test "a hostname that resolves to nothing is unresolved" do
    assert_equal :unresolved, diagnose(www)
  end

  test "a www answering with A records instead of a CNAME is proxied" do
    # Orange cloud: the author's own zone answers with its anycast addresses
    # and hides the CNAME, so the site loads while the hostname never validates.
    diagnosis = build(www, "www.merovex.press" => { a: %w[ 104.21.53.21 172.67.207.200 ] })

    assert_equal :proxied, diagnosis.reason
    assert_match(/DNS-only/, diagnosis.message)
  end

  test "a www CNAME pointing somewhere else is misrouted" do
    assert_equal :misrouted, diagnose(www, "www.merovex.press" => { cname: "example.test" })
  end

  test "an apex flattened onto the target's addresses routes correctly" do
    # An apex can't be a CNAME — the host flattens it — so matching the
    # target's own A records is the only signal available.
    assert_equal :pending, diagnose(apex,
      "merovex.press" => { a: TARGET_IPS },
      TARGET => { a: TARGET_IPS },
      "_acme-challenge.merovex.press" => { txt: "tv" })
  end

  test "an apex flattened onto someone else's addresses is misrouted, not proxied" do
    assert_equal :misrouted, diagnose(apex,
      "merovex.press" => { a: %w[ 203.0.113.9 ] }, TARGET => { a: TARGET_IPS })
  end

  test "correct routing with no TXT in DNS reports the TXT, not the routing" do
    diagnosis = build(www, "www.merovex.press" => { cname: TARGET })

    assert_equal :txt_missing, diagnosis.reason
    assert_match(/_acme-challenge\.www\.merovex\.press/, diagnosis.message)
  end

  test "a TXT with the wrong value is distinguished from a missing one" do
    assert_equal :txt_mismatch, diagnose(www,
      "www.merovex.press" => { cname: TARGET },
      "_acme-challenge.www.merovex.press" => { txt: "stale" })
  end

  test "routing is reported ahead of the TXT — the broken site outranks the pending certificate" do
    assert_equal :misrouted, diagnose(www, "www.merovex.press" => { cname: "example.test" })
  end

  test "a TXT Cloudflare hasn't minted yet is not the author's problem" do
    assert_equal :pending, diagnose(www(records: []), "www.merovex.press" => { cname: TARGET })
  end

  # The case this suite was missing: Cloudflare lists one record per in-flight
  # validation attempt, so a rotated order leaves the published one AND a new
  # one outstanding. Judging only the first said everything was fine while the
  # certificate sat unissued (benwilsondev.com, 2026-08-26).
  test "an earlier record already published doesn't excuse the one still outstanding" do
    diagnosis = build(www(records: [ validation("www.merovex.press", "published"),
                                     validation("www.merovex.press", "outstanding") ]),
      "www.merovex.press" => { cname: TARGET },
      "_acme-challenge.www.merovex.press" => { txt: "published" })

    assert_equal :txt_mismatch, diagnosis.reason
    assert_equal "outstanding", diagnosis.blocking_record.txt_value
    # Add, don't swap — replacing the published value would undo working DNS.
    assert_match(/keep any other values/, diagnosis.message)
  end

  test "every outstanding record published is what settles the TXT check" do
    assert_equal :pending, diagnose(www(records: [ validation("www.merovex.press", "one"),
                                                   validation("www.merovex.press", "two") ]),
      "www.merovex.press" => { cname: TARGET },
      "_acme-challenge.www.merovex.press" => { txt: %w[ one two ] })
  end

  # An author whose own zone is on Cloudflare orange-clouds the record: it
  # answers with THEIR proxy addresses and never exposes the CNAME, so reading
  # DNS alone concludes :proxied and tells them to disable a proxy that is
  # carrying their traffic perfectly well. Cloudflare verified the hostname, so
  # routing demonstrably works and our guess is not evidence.
  test "a hostname Cloudflare has verified is never blamed for its routing" do
    diagnosis = build(www(cloudflare_status: "active", records: []),
      "www.merovex.press" => { a: %w[ 104.21.53.21 172.67.207.200 ] })

    assert_equal :pending, diagnosis.reason
    assert_no_match(/DNS-only/, diagnosis.message)
  end

  test "a verified hostname still reports an outstanding TXT record" do
    diagnosis = build(www(cloudflare_status: "active"),
      "www.merovex.press" => { a: %w[ 104.21.53.21 ] })

    assert_equal :txt_missing, diagnosis.reason
    # Routing is settled, so the build must target the domain regardless.
    assert diagnosis.routed?
  end

  test "a resolver that can't answer says so instead of blaming DNS" do
    diagnosis = CustomDomain::Diagnosis.new(www, cname_target: TARGET, resolver: DeadResolver.new)

    assert_equal :undetermined, diagnosis.reason
    assert_match(/try again/i, diagnosis.message)
  end

  private
    def www(records: [ validation("www.merovex.press", "tv") ], **attributes)
      accounts(:merovex).custom_domains.new(hostname: "www.merovex.press", status: "verifying",
        validation_records: records, **attributes)
    end

    def apex(records: [ validation("merovex.press", "tv") ], **attributes)
      accounts(:merovex).custom_domains.new(hostname: "merovex.press", status: "verifying",
        validation_records: records, **attributes)
    end

    def validation(hostname, value)
      { "txt_name" => "_acme-challenge.#{hostname}", "txt_value" => value }
    end

    def build(domain, zone = {})
      CustomDomain::Diagnosis.new(domain, cname_target: TARGET, resolver: FakeResolver.new(zone))
    end

    def diagnose(domain, zone = {}) = build(domain, zone).reason
end
