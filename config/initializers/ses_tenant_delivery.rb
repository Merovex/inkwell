# aws-actionmailer-ses 1.2.0 forwards only configuration_set_name/email_tags/
# list_management_options from delivery_method_options to the SendEmail call;
# any other key falls through to Aws::SESV2::Client.new and raises. Site and
# platform tenancy (docs/ses-tenants.md) stamps tenant_name the same way, so
# teach the delivery method to forward it — aws-sdk-sesv2 1.105's send_email
# accepts it. Drop this when the gem grows native tenant support.
module SesTenantDelivery
  def initialize(settings = {})
    settings = settings.dup
    tenant_name = settings.delete(:tenant_name)
    super(settings)
    @send_email_params[:tenant_name] = tenant_name if tenant_name
  end
end

Aws::ActionMailer::SESV2::Mailer.prepend(SesTenantDelivery)
