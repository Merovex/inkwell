# One immutable entry in a subscriber's consent log: a state transition stamped
# with when, from where, and the IP. This is the legal proof-of-consent trail —
# events are appended, never edited or reordered. See ADR 0011.
#
# Each event also carries a source_fingerprint — a keyed hash of the IP's
# network neighborhood (ADR 0026). It answers "did these signups come from the
# same place?" across every site on the platform without the raw address, so
# it is the input a future cluster query reads, and it is what lets the raw
# ip_address stay narrowly a consent record.
class SubscriptionEvent < ApplicationRecord
  ACTIONS = %w[ subscribed confirmed unsubscribed resubscribed bounced complained
                 reactivated reinvited ].freeze

  # The two sides of list movement, as the weekly digest counts them: actions
  # that put a subscriber into the sendable pool, and the ones that take them
  # out (one definition — SubscriberSnapshot and WeeklyReport both read it).
  JOINED   = %w[ confirmed resubscribed reactivated ].freeze
  DEPARTED = %w[ unsubscribed bounced complained ].freeze

  belongs_to :subscriber

  validates :action, inclusion: { in: ACTIONS }

  before_create { self.source_fingerprint ||= self.class.fingerprint(ip_address) }

  # Same clock as DeliveryEvent#happened_at, so the two ledgers interleave.
  alias_attribute :happened_at, :created_at

  # Append-only: an event is a historical fact. Creating is allowed; changing a
  # persisted one is not.
  before_update { raise ActiveRecord::ReadOnlyRecord, "subscription events are append-only" }

  # The neighborhood, not the address: an IPv4 /24 or IPv6 /56, HMAC'd with a
  # key derived from secret_key_base (so no credential to provision, and the
  # small IPv4 space can't be brute-forced back from the hash). Same source →
  # same fingerprint, on every site. Nil for a blank or unparseable IP.
  def self.fingerprint(ip)
    return if ip.blank?

    address = IPAddr.new(ip.to_s)
    network = address.ipv4? ? address.mask(24) : address.mask(56)
    OpenSSL::HMAC.hexdigest("SHA256", fingerprint_key, "#{network}/#{network.prefix}")
  rescue IPAddr::InvalidAddressError
    nil
  end

  def self.fingerprint_key
    @fingerprint_key ||= Rails.application.key_generator.generate_key("subscription_event/source_fingerprint", 32)
  end
  private_class_method :fingerprint_key
end
