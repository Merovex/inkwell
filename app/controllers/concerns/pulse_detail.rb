# Loads a Pulse check's detail — for the in-board Pulse checks view and the
# standalone pulse page. The commitment is WEEKLY even when the prompt asks
# daily, so answers are grouped by ISO week: this week's answers, who still owes
# one (excluding you — you get the composer, not a third-person sentence), and
# the earlier weeks. One beats load, grouped in Ruby.
module PulseDetail
  extend ActiveSupport::Concern

  private
    def load_pulse_detail(record, week_of: Time.zone.today)
      @record = record
      @pulse = record.recordable
      @week_start = week_of.beginning_of_week
      @is_current_week = @week_start == Time.zone.today.beginning_of_week

      by_week = @pulse.beats.to_a.group_by { |beat| beat.asked_on.beginning_of_week }
      @beats = (by_week[@week_start] || []).sort_by(&:asked_on)
      @my_beat = @beats.find { |beat| beat.creator_id == Current.user.id }
      @answered_ids = @beats.map(&:creator_id).uniq
      @answered_this_week = @answered_ids.size
      # Owe an answer this week — but not you (you compose), so no one reads a
      # sentence about themselves.
      @non_answerers = @pulse.respondents
        .where.not(id: @answered_ids + [ Current.user.id ])
        .includes(avatar_attachment: :blob)
      # [[week_start, [beats]], …] most recent first.
      @earlier_weeks = by_week.except(@week_start).sort.reverse

      # Comment counts for every answer shown — peer response lives here too.
      shown = @beats + @earlier_weeks.flat_map(&:last)
      @comment_counts = @circle.records.active.comments
        .where(parent_id: shown.map(&:record_id)).group(:parent_id).count
    end
end
