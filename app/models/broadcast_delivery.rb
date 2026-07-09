# One subscriber's copy of a broadcast: created when the fan-out reaches them,
# stamped sent_at once the email is handed off. The (broadcast, subscriber)
# unique index makes re-runs safe. Engagement milestones (delivered/opened/…)
# are stamped the first time Mailgun reports them, which also bumps the
# broadcast's cached counter — so opens and clicks count unique recipients.
class BroadcastDelivery < ApplicationRecord
  belongs_to :broadcast
  belongs_to :subscriber

  # Mailgun event name → [ this delivery's milestone column, broadcast counter ].
  EVENTS = {
    "delivered"    => [ :delivered_at,    :delivered_count ],
    "opened"       => [ :opened_at,       :opened_count ],
    "clicked"      => [ :clicked_at,      :clicked_count ],
    "failed"       => [ :bounced_at,      :bounced_count ],
    "bounced"      => [ :bounced_at,      :bounced_count ],
    "complained"   => [ :complained_at,   :complained_count ],
    "unsubscribed" => [ :unsubscribed_at, :unsubscribed_count ]
  }.freeze

  # Record a Mailgun engagement event once (first-event-wins → unique
  # opens/clicks): stamp this recipient and bump the broadcast's cached counter.
  # Unknown events and repeats are no-ops. Returns true only on the first stamp.
  def record_event!(mailgun_event)
    column, counter = EVENTS[mailgun_event]
    return false unless column
    return false if self[column]

    transaction do
      update!(column => Time.current)
      broadcast.increment!(counter)
    end
    true
  end
end
