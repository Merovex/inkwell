# The Progress leaderboard's read model: for a circle's weekly Pulse check, each
# member's standing — their beat this occurrence, the words they logged, and
# their run (consecutive occurrences answered) — plus the circle's roll-ups.
# One beats load; everything else computed in Ruby (a leaderboard, not a hot
# path). The "occurrences" are the ask-days the pulse actually recorded beats
# on, so a run is consecutive answered ask-days, not consecutive calendar weeks.
class Circle::Ledger
  # How many recent occurrences the run sparkline shows.
  WEEKS_SHOWN = 6

  Standing = Struct.new(:member, :beat, :words, :run, :prior, :broken, :bars, :you,
    keyword_init: true) do
    def posted? = beat.present?
  end

  def initialize(circle, viewer: Current.user)
    @circle = circle
    @viewer = viewer
    @pulse = circle.pulse
    @beats = @pulse ? @pulse.beats.to_a : []
    @by_member = @beats.group_by(&:creator_id)
    @occurrences = @beats.map(&:asked_on).uniq.sort   # ascending
    @current = @occurrences.last
  end

  attr_reader :pulse

  def standings
    @standings ||= @circle.roster.map { |member| standing_for(member) }
  end

  def posted_this_week = standings.count(&:posted?)
  def member_count = @circle.circle_memberships.count
  def total_words = @beats.sum { |beat| beat.word_count.to_i }

  # The circle's longest active run, for the header stat — nil until someone
  # has a run going.
  def longest = standings.select { |s| s.run.positive? }.max_by(&:run)

  private
    def standing_for(member)
      beats = @by_member[member.id] || []
      answered = beats.map(&:asked_on).to_set
      this_beat = @current && beats.find { |beat| beat.asked_on == @current }
      run, prior, broken = run_info(answered)
      bars = @occurrences.last(WEEKS_SHOWN).map { |occ| answered.include?(occ) }
      Standing.new(member: member, beat: this_beat, words: this_beat&.word_count,
        run: run, prior: prior, broken: broken, bars: bars, you: member.id == @viewer&.id)
    end

    # run: consecutive occurrences answered ending at the CURRENT occurrence
    # (0 if the latest was missed). When the latest is missed but an earlier
    # streak existed, broken is true and prior is that streak's length ("was 5").
    def run_info(answered)
      return [ 0, nil, false ] if answered.empty? || @occurrences.empty?
      idx = @occurrences.rindex { |occ| answered.include?(occ) }  # latest answered
      streak = streak_ending(idx, answered)
      if @occurrences[idx] == @current
        [ streak, nil, false ]    # active, unbroken
      else
        [ 0, streak, true ]       # missed the latest — broken, was `streak`
      end
    end

    def streak_ending(idx, answered)
      return 0 if idx.nil?
      count = 0
      while idx >= 0 && answered.include?(@occurrences[idx])
        count += 1
        idx -= 1
      end
      count
    end
end
