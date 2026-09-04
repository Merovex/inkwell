# One subscriber's run through a Drip (their "enrollment"). enrolled_at — the
# subscriber's confirmation time — anchors every Drop's send. A Stream ends when
# the subscriber unsubscribes or finishes the sequence; it is never re-run
# (unique per subscriber + drip). drip_record_id points at the Drip's stable
# Record, so the run survives edits to the campaign.
class Stream < ApplicationRecord
  belongs_to :subscriber
  belongs_to :drip_record, class_name: "Record"
  has_many :deliveries, class_name: "DropDelivery", dependent: :destroy

  # Uniqueness is enforced by the DB index (unique [subscriber_id, drip_record_id]),
  # which lets Drip#enroll use create_or_find_by! to be idempotent on re-confirm —
  # a model validation would raise before the index could catch the race.
  scope :active, -> { where(ended_at: nil) }

  def drip = drip_record.recordable

  # How far this run has got, for the campaign's roster and the subscriber's
  # card. Counted in Ruby off the loaded association so a roster preloading
  # :deliveries answers without a query per row.
  def sent_count = deliveries.count(&:status_sent?)

  # When the next Drop is due, or nil when the sequence is finished (or ended).
  # `steps` is an argument so a roster of many streams through one campaign
  # loads its Drops once instead of once per row.
  def next_send_at(steps: drip.drops, now: Time.current)
    return if ended_at

    recorded = deliveries.map(&:drop_record_id)
    steps.reject { |drop| recorded.include?(drop.record_id) }
      .map { |drop| drop.send_at_for(self) }
      .select { |at| at > now }
      .min
  end

  # Where the run stands, as the admin says it: still going, finished the
  # sequence, or stopped early (and why — "unsubscribed", "bounced", …).
  def outcome(steps: drip.drops)
    if ended_at then ended_reason.presence || "stopped"
    elsif next_send_at(steps:) then "running"
    else "finished"
    end
  end

  # Send every Drop now due to this subscriber, or record a skip if they've
  # become ineligible by the time it comes due — unsubscribed here, or on the
  # platform's cross-site suppression list for this site (Subscriber#suppressed?,
  # ADR 0027; skip_reason "suppressed"). Idempotent: a delivery already
  # sent/skipped is left alone, so re-running the tick — or a retried job —
  # never re-mails. Drops come due in position order.
  def advance!(now: Time.current)
    return if ended_at

    due_drops(now:).each do |drop|
      delivery = deliveries.create_or_find_by!(drop_record: drop.record) { |d| d.subscriber = subscriber }
      next unless delivery.status_pending?

      if !subscriber.confirmed?
        delivery.update!(status: :skipped, skip_reason: subscriber.status)
      elsif subscriber.suppressed?
        delivery.update!(status: :skipped, skip_reason: "suppressed")
      else
        message = DropMailer.step(self, drop).deliver_now
        # The dispatch stamp (which ESP + its message id) is what lets a later
        # bounce or complaint be attributed to this exact send.
        delivery.update!(status: :sent, sent_at: Time.current, **DeliveryEvent.dispatch_stamp(message))
      end
    end
  end

  # Drops whose scheduled day has arrived (enrolled_at + delay_days ≤ now) and
  # that haven't been recorded yet, in send order.
  def due_drops(now: Time.current)
    recorded = deliveries.pluck(:drop_record_id)
    drip.drops.reject { |drop| recorded.include?(drop.record_id) || drop.send_at_for(self) > now }
  end

  # Close the run (unsubscribed / completed). Idempotent.
  def end!(reason)
    update!(ended_at: Time.current, ended_reason: reason) unless ended_at
  end
end
