# One canonical email-delivery event. Each ESP webhook controller verifies its
# own signature, translates its payload into this provider-agnostic vocabulary,
# and everything downstream — suppression, subscriber status, the dashboard
# counters — reads only the canonical form and never knows which ESP produced
# it. The raw payload rides along so a wrong mapping can be replayed rather
# than guessed.
#
# The vocabulary's two easy-to-get-wrong members: `suppressed` means the ESP
# refused to send because the address was already on its suppression list — it
# says nothing new about the mailbox; `rejected` is an ISP/policy refusal about
# our sending reputation, not their address. Neither may touch the subscriber:
# treating either as a hard bounce quietly kills live subscribers while hiding
# the sending problem that caused it.
class DeliveryEvent < ApplicationRecord
  belongs_to :subscriber, optional: true
  belongs_to :delivery, polymorphic: true, optional: true

  enum :provider, %w[ postmark ses ].index_by(&:itself)
  enum :event, %w[ delivered opened clicked soft_bounce hard_bounce
                   complaint suppressed rejected ].index_by(&:itself)

  # Canonical event → the milestone the delivery models stamp (first-event-wins,
  # drives the /admin/broadcasts counters). suppressed and rejected are absent
  # on purpose — no mail reached (or will reach) the recipient's mailbox
  # because of *us*, so they must not read as recipient failures.
  MILESTONES = {
    "delivered"   => "delivered",
    "opened"      => "opened",
    "clicked"     => "clicked",
    "hard_bounce" => "bounced",
    "complaint"   => "complained"
  }.freeze

  # This many soft bounces in a row (no successful delivery in between) and the
  # mailbox is effectively dead — suppress like a hard bounce.
  SOFT_BOUNCE_LIMIT = 3

  # The ingest boundary: record the event once and apply its side effects only
  # on first sight. The [provider, message id, event] unique index makes the
  # dedupe race-proof — a webhook retry finds the existing row and does nothing.
  def self.ingest!(provider:, event:, payload:, provider_message_id: nil,
                   recipient: nil, occurred_at: nil, delivery: nil)
    record = create_or_find_by!(provider:, provider_message_id:, event:) do |e|
      e.payload = payload
      e.recipient = recipient
      e.occurred_at = occurred_at
      e.delivery = delivery
      e.subscriber = delivery&.subscriber
    end
    record.apply! if record.previously_new_record?
    record
  end

  # Which ESP actually carried a just-sent message, read off the header its
  # delivery method writes back after the API call (postmark sets
  # X-PM-Message-Id, aws-actionmailer-ses sets ses_message_id). Merge into the
  # delivery's dispatch update! so bounces can be attributed to the exact send.
  # Empty under the :test delivery method — the columns just stay nil.
  def self.dispatch_stamp(message)
    if (id = message.header["X-PM-Message-Id"]&.value).present?
      { provider: "postmark", provider_message_id: id }
    elsif (id = message.header["ses_message_id"]&.value).present?
      { provider: "ses", provider_message_id: id }
    else
      {}
    end
  end

  # The downstream consequences, in canonical terms only. Milestones stamp the
  # dashboard; suppression flows through the Subscriber state methods (which
  # append to the consent trail). suppressed/rejected are record-only.
  def apply!
    delivery&.record_event!(MILESTONES[event]) if MILESTONES[event]

    case event
    when "hard_bounce" then subscriber&.mark_bounced!(source: provider)
    when "complaint"   then subscriber&.mark_complained!(source: provider)
    when "soft_bounce" then suppress_soft_bounced if soft_bounce_exhausted?
    end
  end

  private
    # "Consecutive" means since the last successful delivery — any delivered
    # event resets the streak. Counts this event too (it's already persisted).
    def soft_bounce_exhausted?
      return false unless subscriber

      events = self.class.where(subscriber:)
      streak = events.soft_bounce
      if (last_delivered = events.delivered.maximum(:created_at))
        streak = streak.where(created_at: last_delivered..)
      end
      streak.count >= SOFT_BOUNCE_LIMIT
    end

    def suppress_soft_bounced
      delivery&.record_event!("bounced")
      subscriber.mark_bounced!(source: provider)
    end
end
