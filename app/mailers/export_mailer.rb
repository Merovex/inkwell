class ExportMailer < ApplicationMailer
  # Transactional identity/config set, like sign-in mail — bounce/complaint
  # only, no open/click tracking; platform-auth tenant, same as the rest of
  # the platform's operational mail.
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :transactional_config_set),
    tenant_name: "platform-auth"
  }

  # Sent by Export#build! once the zip is attached. The link goes to the
  # signed-in Export page, never to the file: the archive holds the
  # subscriber list, so an emailed URL must not be enough to fetch it.
  def ready(export)
    @export = export
    @site_name = export.account.site.site_name
    @exports_url = admin_exports_url(script_name: "/#{export.account.slug}", **app_url_options)
    mail to: export.creator.email_address, subject: "Your #{@site_name} export is ready"
  end
end
