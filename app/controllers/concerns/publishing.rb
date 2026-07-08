# Reads the composer's publish/schedule controls — the Publish button and the
# shared scheduler panel's fields (shared/_scheduler) — for any publishable
# resource's controller (posts, messages).
module Publishing
  extend ActiveSupport::Concern

  private
    def publishing?
      params[:publish].present?
    end

    def scheduling?
      params[:scheduled_posting] == "true"
    end

    # The panel's "unschedule and save" submits scheduled_posting=false
    # ("Post now instead" also sends false, but publish wins the ladder).
    def unscheduling?
      params[:scheduled_posting] == "false" && !publishing?
    end

    # "2026-07-04" + hour 9 → that day at 9:00 in the browser's zone (falling
    # back to the app zone if the hidden zone field didn't make it). A
    # tampered or missing date or hour parses to nil rather than a 500
    # (Date::Error and zone.local's out-of-range are both ArgumentErrors);
    # callers treat nil like a past time and reject the schedule.
    def scheduled_at
      @scheduled_at ||= begin
        zone = Time.find_zone(params[:scheduled_posting_at_zone]) || Time.zone
        date = Date.iso8601(params[:scheduled_posting_at_date].to_s)
        zone.local(date.year, date.month, date.day, params[:scheduled_posting_at_hour].to_i)
      rescue ArgumentError
        nil
      end
    end

    def initial_status
      publishing? ? :published : :drafted
    end
end
