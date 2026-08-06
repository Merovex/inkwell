# The Pulse check ask — user bulk (stream 2, docs/email-architecture.md):
# scheduled platform mail to a circle member, so it rides the platform bulk
# identity, never the verification one.
class PulseMailer < ApplicationMailer
  # Bulk config set: complaint/bounce events flow like the newsletter's. The
  # platform-circles tenant stamp isolates this lane's reputation from auth
  # mail and from every site's newsletter (docs/ses-tenants.md).
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :marketing_config_set),
    tenant_name: "platform-circles"
  }

  def ask(pulse, user, asked_on)
    @pulse = pulse
    @circle = pulse.record.bucket
    @asked_on = asked_on
    # The answer page lives on the app host (the circle area), not a press site
    # — app_url_options pins the host once enforcement is on (ADR 0018).
    @answer_url = circle_pulse_url(@circle, pulse.record, **app_url_options)

    # The question is the subject (the circle is named in the body/from context).
    mail(to: user.email_address, from: platform_bulk_from, subject: @pulse.question.truncate(120))
  end
end
