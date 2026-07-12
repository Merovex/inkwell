# One subscriber's copy of a broadcast: created when the fan-out reaches them,
# stamped sent_at once the email is handed off. The (broadcast, subscriber)
# unique index makes re-runs safe. Engagement milestones (delivered/opened/…)
# are stamped the first time SES reports them (via Webhooks::SesController), which
# also bumps the broadcast's cached counter — so opens and clicks count unique
# recipients.
class BroadcastDelivery < ApplicationRecord
  belongs_to :broadcast
  belongs_to :subscriber

  # Opens and clicks count as engagement — they reset the subscriber's sunset clock.
  ENGAGEMENT = %w[ opened clicked ].freeze

  # Internal event name → [ this delivery's milestone column, broadcast counter ].
  # Webhooks::SesController translates SES event types into these names; the
  # app-side unsubscribe path records "unsubscribed" directly.
  EVENTS = {
    "delivered"    => [ :delivered_at,    :delivered_count ],
    "opened"       => [ :opened_at,       :opened_count ],
    "clicked"      => [ :clicked_at,      :clicked_count ],
    "failed"       => [ :bounced_at,      :bounced_count ],
    "bounced"      => [ :bounced_at,      :bounced_count ],
    "complained"   => [ :complained_at,   :complained_count ],
    "unsubscribed" => [ :unsubscribed_at, :unsubscribed_count ]
  }.freeze

  # Record an engagement event once (first-event-wins → unique opens/clicks):
  # stamp this recipient and bump the broadcast's cached counter. Unknown events
  # and repeats are no-ops. Returns true only on the first stamp.
  def record_event!(event)
    column, counter = EVENTS[event]
    return false unless column
    return false if self[column]

    transaction do
      update!(column => Time.current)
      broadcast.increment!(counter)
      subscriber.mark_engaged! if ENGAGEMENT.include?(event)
    end
    true
  end
end
