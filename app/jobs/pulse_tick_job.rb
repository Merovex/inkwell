# Pulse heartbeat (config/recurring.yml): every 30 minutes, fire each live
# pulse whose cadence lands today and whose ask time has passed, unless it
# already asked today. A deliberate cross-circle sweep, so it declares itself to
# the tenancy guard. Idempotent — the last_asked_on stamp prevents a second ask.
class PulseTickJob < ApplicationJob
  def perform
    now = Time.zone.now
    today = now.to_date
    now_minutes = now.hour * 60 + now.min

    Current.allowing_unscoped_tenancy do
      Pulse.live.find_each do |pulse|
        next if pulse.last_asked_on == today
        next unless pulse.due_on?(today)
        next unless now_minutes >= pulse.ask_at_minutes

        pulse.ask!(today)
      end
    end
  end
end
