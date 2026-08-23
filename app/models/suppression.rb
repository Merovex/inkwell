# One row in the cross-site suppression ledger (ADR 0027): "this Person should
# not be mailed" — by any site (scope nil) or by one Account — together with
# the reversals that lift it. Append-only: nothing is updated or deleted.
# Lifting a suppression is a row too, pointing at the row it lifts, so the
# history of who un-suppressed what, and when, is kept.
#
# Who writes what:
#   hard_bounce  → imposed globally, from the delivery ledger (DeliveryEvent).
#                  A dead mailbox is a fact about the address, not one author.
#   complaint    → imposed for the Account that sent the mail (a reader who
#                  flags author A as spam may still want author B); escalates
#                  to global once ESCALATE_AFTER distinct sites are involved.
#                  A complaint we can't attribute to a site is imposed globally.
#   manual       → console-imposed (no UI by design), or an admin's lift
#                  (Subscriber#reactivate!) — site-scoped, so one site's
#                  say-so never speaks for another.
#   reconfirmed  → lift written by Subscriber#confirm!: a fresh double opt-in
#                  is proof the mailbox works (lifts global rows) and that the
#                  reader wants that site (lifts that site's rows).
#
# This table is a projection; DeliveryEvent and SubscriptionEvent are the
# record. Doubt it → rebuild! replays them.
class Suppression < ApplicationRecord
  belongs_to :person
  belongs_to :scope, polymorphic: true, optional: true   # nil = every site
  belongs_to :lifted, class_name: "Suppression", optional: true

  IMPOSING_REASONS = %w[ hard_bounce complaint manual ].freeze
  LIFTING_REASONS  = %w[ manual reconfirmed ].freeze
  enum :reason, (IMPOSING_REASONS | LIFTING_REASONS).index_by(&:itself)

  # Complaints against this many distinct sites make it a fact about the
  # reader's wishes, not one author's list.
  ESCALATE_AFTER = 2

  before_update { raise ActiveRecord::ReadOnlyRecord, "suppressions are append-only" }

  scope :imposing, -> { where(lifted_id: nil) }
  scope :lifting,  -> { where.not(lifted_id: nil) }

  def lift? = lifted_id.present?

  # Every row that speaks for this scope: global rows, plus the scope's own.
  def self.covering(scope)
    scope ? where(scope: nil).or(where(scope: scope)) : where(scope: nil)
  end

  # Suppressions currently binding on `scope` (nil = the global list): imposed
  # rows that cover it, minus any with a lift that covers it. An account-scoped
  # lift of a global row frees that site only; the global row still binds
  # every other site.
  def self.in_force_for(scope = nil)
    imposing.covering(scope).where.not(id: lifting.covering(scope).select(:lifted_id))
  end

  # Same, but only rows imposed at exactly this scope — not the global ones
  # that also happen to cover it.
  def self.in_force_at(scope)
    imposing.where(scope: scope).where.not(id: lifting.covering(scope).select(:lifted_id))
  end

  # Write a suppression unless an identical one is already in force at that
  # exact scope (ingest retries and rebuilds must not stack duplicates).
  # Returns the row, or nil when nothing new was written.
  def self.impose!(person:, reason:, scope: nil, at: Time.current)
    reason = reason.to_s
    return if in_force_at(scope).where(person:, reason:).exists?

    create!(person:, reason:, scope:, created_at: at).tap do
      escalate!(person, at:) if reason == "complaint" && scope
    end
  end

  # Lift everything binding on `scope` for this person, with lifts at that
  # scope — so a site's lift of a global suppression frees that site alone,
  # while a global lift (nil scope) frees everyone. Returns the lift rows.
  def self.lift!(person:, reason:, scope: nil, at: Time.current)
    in_force_for(scope).where(person:).map do |suppression|
      create!(person:, reason:, scope:, lifted: suppression, created_at: at)
    end
  end

  # Replay the ledgers in time order: delivery events impose (hard bounce →
  # global, complaint → the sending site or global if unattributed); consent
  # events lift (confirmed → proof of life; reactivated → that site's admin
  # vouched). Soft-bounce exhaustion deliberately writes nothing here — it
  # suppresses the Subscriber (DeliveryEvent) but is not a fact about the
  # mailbox for other sites. Pre-ledger bounced/complained subscribers (before
  # ADR 0025) are not reconstructed: their status already blocks them on the
  # one site that existed, and the ledger is the only cross-site authority.
  def self.rebuild!
    transaction do
      delete_all

      imposers = DeliveryEvent.where(event: %w[ hard_bounce complaint ]).where.not(person_id: nil).includes(subscriber: :account)
      lifters  = SubscriptionEvent.where(action: %w[ confirmed reactivated ]).includes(subscriber: %i[ person account ])

      (imposers + lifters).sort_by { [ it.happened_at, it.id ] }.each do |event|
        case event
        when DeliveryEvent then impose_from(event)
        when SubscriptionEvent then lift_from(event)
        end
      end
    end
  end

  class << self
    private
      def impose_from(event)
        if event.hard_bounce?
          impose!(person: event.person, reason: :hard_bounce, at: event.happened_at)
        else
          impose!(person: event.person, reason: :complaint, scope: event.subscriber&.account, at: event.happened_at)
        end
      end

      def lift_from(event)
        person, account, at = event.subscriber.person, event.subscriber.account, event.happened_at
        if event.action == "confirmed"
          lift!(person:, reason: :reconfirmed, at:)
          lift!(person:, reason: :reconfirmed, scope: account, at:)
        else
          lift!(person:, reason: :manual, scope: account, at:)
        end
      end

      def escalate!(person, at: Time.current)
        sites = imposing.complaint.where(person:).where.not(scope_id: nil).distinct.count(:scope_id)
        impose!(person:, reason: :complaint, at:) if sites >= ESCALATE_AFTER
      end
  end
end
