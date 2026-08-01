# Normalises and validates a hostname the author typed into the "Connect your
# domain" form (onboarding step 1). The rules mirror the runbook: downcase,
# strip any scheme / path / port / trailing dot, and reject anything that isn't
# a plain registrable hostname. Our own namespace (kindredquill.com and its
# subdomains) is refused — that's ours, not theirs.
#
# Value object: `Hostname.new(input)` then #normalized / #valid? / #error.
# Non-ASCII input must already be in punycode (xn--) form — we validate the
# ASCII result rather than guess an IDN encoding without a library.
class Hostname
  NAMESPACE = "kindredquill.com"

  # A conservative registrable-hostname shape: dot-separated labels of
  # letters/digits/hyphens (no leading/trailing hyphen), at least two labels,
  # a TLD of 2+ letters. Punycode labels (xn--…) pass as ordinary a-z0-9-.
  LABEL = /[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?/
  FORMAT = /\A#{LABEL}(?:\.#{LABEL})*\.[a-z]{2,}\z/

  attr_reader :normalized, :error

  def initialize(input)
    @normalized = normalize(input)
    @error = validate
  end

  def valid? = @error.nil?

  # The bare apex for a hostname: drops a leading "www." (the two are the same
  # site). "www.merovex.press" and "merovex.press" both apex to "merovex.press".
  def apex = @normalized&.delete_prefix("www.")

  # Both hostnames we onboard for an apex: the apex itself and its www. — two
  # KV keys, two custom hostnames, one canonical (www, which authors can CNAME).
  def onboarding_set
    return [] unless valid?
    [ apex, "www.#{apex}" ]
  end

  def canonical = valid? ? "www.#{apex}" : nil

  private
    def normalize(input)
      host = input.to_s.strip.downcase
      host = host.sub(%r{\A[a-z][a-z0-9+.-]*://}, "") # strip scheme
      host = host.split(%r{[/?#]}, 2).first.to_s      # strip path/query/fragment
      host = host.split("@", 2).last.to_s             # strip any userinfo
      host = host.sub(/:\d+\z/, "")                    # strip port
      host = host.delete_prefix(".").delete_suffix(".") # strip stray dots
      host.presence
    end

    def validate
      return "Enter a domain" if @normalized.blank?
      return "Enter the domain in ASCII or punycode form" unless @normalized.ascii_only?
      return "That doesn't look like a domain" unless @normalized.match?(FORMAT)
      if @normalized == NAMESPACE || @normalized.end_with?(".#{NAMESPACE}")
        return "That's our domain — connect a domain you own"
      end
      nil
    end
end
