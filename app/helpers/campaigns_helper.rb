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
end
