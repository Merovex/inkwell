# View copy for the re-skinned Campaigns admin (models stay Drip/Drop). Pure
# presentation — turns the existing trigger / delay data into the mockup's
# sentences.
module CampaignsHelper
  # "Starts when a subscriber confirms" — the human phrase for a campaign's
  # trigger. Only "confirmed" exists today; unknowns fall back gracefully.
  def campaign_start_phrase(trigger)
    { "confirmed" => "Starts when a subscriber confirms" }
      .fetch(trigger, "Starts when #{trigger.to_s.humanize.downcase}")
  end

  # "4 steps over 5 days" (the span is dropped when every step is day 0).
  def campaign_shape(steps, span)
    shape = pluralize(steps, "step")
    shape += " over #{pluralize(span, 'day')}" if span.positive?
    shape
  end

  # The relative gap shown under a step's absolute day: "on confirm" for day 0,
  # else "N day(s) later" than the previous step.
  def step_delta(delay_days, previous)
    return "on confirm" if delay_days.zero?
    gap = delay_days - previous
    gap.positive? ? "#{pluralize(gap, 'day')} later" : "same day"
  end

  # One run's state, as a badge. Stream#outcome answers "running"/"finished" or
  # the reason it stopped ("unsubscribed", "bounced", "complained"), and a stop
  # is the only one that reads as trouble.
  DRIP_OUTCOMES = {
    "running" => [ "In progress", "accent" ],
    "finished" => [ "Finished", "success" ]
  }.freeze

  def drip_outcome_label(outcome) = DRIP_OUTCOMES.dig(outcome, 0) || outcome.humanize

  def drip_outcome_variant(outcome) = DRIP_OUTCOMES.dig(outcome, 1) || "warning"

  # "2 of 4 sent · next Sep 5" — where a run has got to, and when it moves
  # again. Steps are passed in so a roster loads the campaign's Drops once.
  def drip_progress_phrase(stream, steps:, total:)
    phrase = "#{stream.sent_count} of #{total} sent"
    if (next_at = stream.next_send_at(steps: steps))
      phrase += " · next #{l next_at.to_date, format: :short}"
    elsif stream.ended_at
      phrase += " · stopped #{l stream.ended_at.to_date, format: :short}"
    end
    phrase
  end
end
