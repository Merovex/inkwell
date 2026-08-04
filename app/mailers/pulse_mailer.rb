# The Pulse check ask. A transactional note to a circle member (a real user), so it
# rides the kindredquill.com support identity ApplicationMailer defaults to — not
# a press's newsletter identity — on the default transactional stream.
class PulseMailer < ApplicationMailer
  def ask(pulse, user, asked_on)
    @pulse = pulse
    @circle = pulse.record.bucket
    @asked_on = asked_on
    # The answer page lives on the app host (the circle area), not a press site
    # — app_url_options pins the host once enforcement is on (ADR 0018).
    @answer_url = circle_pulse_url(@circle, pulse.record, **app_url_options)

    # The question is the subject (the circle is named in the body/from context).
    mail(to: user.email_address, subject: @pulse.question.truncate(120))
  end
end
