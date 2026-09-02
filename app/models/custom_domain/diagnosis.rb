require "resolv"

# Why a custom domain hasn't validated yet, answered from public DNS.
#
# "Waiting for DNS" is the same sentence whether the record is missing, points
# somewhere else, is proxied at the author's own DNS host, or is correct and
# simply waiting on Cloudflare — but each needs a different move from the
# author, so the check badge names the first unmet precondition instead of
# spinning. The proxied case is the one worth catching: an orange-clouded
# record hides the CNAME behind Cloudflare's anycast addresses and terminates
# TLS with the author's own certificate, so the site can look perfectly fine
# while this hostname never finishes validating.
#
# Routing is checked before the TXT, worst first: a wrong CNAME breaks the
# site, a missing TXT only holds up the certificate.
class CustomDomain::Diagnosis
  # This runs inline in the check request — a slow resolver must never hold it.
  TIMEOUT = 2

  # Test seam, matching CustomDomainStatusJob.client_override: a canned zone
  # so the suite never asks the real network a question it can't control.
  cattr_accessor :resolver_override

  def initialize(domain, cname_target:, resolver: nil)
    @domain = domain
    @cname_target = cname_target
    @resolver = resolver
  end

  def reason
    return @reason if defined?(@reason)

    @reason = begin
      if routing_settled? then txt_fault || :pending
      elsif cname.nil? && addresses.empty? then :unresolved
      else routing_fault || txt_fault || :pending
      end
    rescue Resolv::ResolvError, Resolv::ResolvTimeout, IOError, SystemCallError
      :undetermined
    end
  end

  # Cloudflare has verified the hostname itself, so routing demonstrably works
  # Does DNS already point this hostname at us? True while the certificate is
  # still pending — reaching the TXT checks at all means the records resolve
  # here, and everything left is Cloudflare's side of the handshake. The build
  # target keys off this: where a site is mounted is a DNS question, not a TLS
  # one.
  ROUTED = %i[ txt_missing txt_mismatch pending ].freeze
  def routed? = ROUTED.include?(reason)

  # The first outstanding record DNS doesn't already satisfy — what the author
  # has to do next, named exactly. Nil once every record is published.
  def blocking_record
    return @blocking_record if defined?(@blocking_record)

    @blocking_record = @domain.validation_records.find do |record|
      txt_values(record.txt_name).exclude?(record.txt_value)
    end
  end

  def message
    case reason
    when :unresolved
      "#{hostname} isn't resolving yet. Add the DNS records below — new records usually appear within a few minutes."
    when :misrouted
      "#{hostname} resolves, but not to #{@cname_target}. Point it there using the records below."
    when :proxied
      "#{hostname} is proxied at your DNS host (Cloudflare's orange cloud), which hides the CNAME the " \
      "certificate validates against. Set it to DNS-only — the site may look fine meanwhile, but the " \
      "hostname will never finish."
    when :txt_missing
      "#{hostname} points here correctly. The TXT record #{blocking_record.txt_name} isn't in DNS yet — " \
      "add it exactly as shown below."
    when :txt_mismatch
      "#{hostname} points here correctly, but #{blocking_record.txt_name} doesn't carry the value Cloudflare " \
      "is waiting for. Add the value shown below — keep any other values already on that name."
    when :undetermined
      "Couldn't read DNS just now. Try again in a moment."
    else
      "DNS for #{hostname} looks right — waiting on Cloudflare to issue the certificate, usually a few minutes."
    end
  end

  private
    def hostname = @domain.hostname

    # Cloudflare has verified the hostname itself, so routing demonstrably
    # works and our own resolver's reading of it is not evidence of anything.
    # This matters for an author whose zone is also on Cloudflare: an
    # orange-clouded record answers with THEIR proxy addresses and never
    # exposes the CNAME, so the checks below conclude :proxied and tell them to
    # turn off a proxy that is carrying their traffic perfectly well.
    # Believing our guess over Cloudflare's answer sent exactly that advice to
    # a working domain (2026-08-26).
    def routing_settled?
      CustomDomain::ACTIVE_HOSTNAME_STATUSES.include?(@domain.cloudflare_status)
    end

    # A CNAME must name the target. An apex can't be a CNAME — DNS hosts
    # flatten it to A records — so it has to land on the target's own
    # addresses instead. A subdomain answering with A records rather than a
    # CNAME is proxied (or hand-rolled as an A record); the fix is the same.
    def routing_fault
      if cname
        :misrouted unless same_host?(cname, @cname_target)
      elsif (addresses & target_addresses).any?
        nil
      elsif apex?
        :misrouted
      else
        :proxied
      end
    end

    # Nothing to check until Cloudflare has minted the records — the page says
    # as much on its own. Every outstanding record has to be published, not
    # just the first: a rotated order leaves two pending, and reporting on one
    # of them let an author satisfy the record we named while the one actually
    # blocking issuance went unmentioned.
    def txt_fault
      return if blocking_record.nil?

      txt_values(blocking_record.txt_name).empty? ? :txt_missing : :txt_mismatch
    end

    # The onboarding only ever instructs an apex and its www (see the DNS
    # instructions on admin/custom_domains#index), so this needs no public
    # suffix list.
    def apex? = !hostname.start_with?("www.")

    def same_host?(one, other) = one.to_s.downcase.chomp(".") == other.to_s.downcase.chomp(".")

    def cname
      return @cname if defined?(@cname)
      @cname = lookup(hostname, Resolv::DNS::Resource::IN::CNAME).first&.name&.to_s
    end

    def addresses = @addresses ||= lookup(hostname, Resolv::DNS::Resource::IN::A).map { |a| a.address.to_s }

    def target_addresses
      @target_addresses ||= lookup(@cname_target, Resolv::DNS::Resource::IN::A).map { |a| a.address.to_s }
    end

    # Memoised per name — the apex and its www validate under different names,
    # and a name can carry several records.
    def txt_values(name)
      @txt_values ||= {}
      @txt_values[name] ||= lookup(name, Resolv::DNS::Resource::IN::TXT).flat_map(&:strings)
    end

    def lookup(name, type) = resolver.getresources(name.to_s, type)

    def resolver
      @resolver ||= resolver_override || Resolv::DNS.new.tap { |dns| dns.timeouts = TIMEOUT }
    end
end
