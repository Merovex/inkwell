# deliver_later renders the mail inside this job — and ActionMailer's stock
# MailDeliveryJob doesn't descend from ApplicationJob, so without this prepend
# mailers would render without Current.account (breaking Site lookups).
# Wired up via config.action_mailer.delivery_job in application.rb.
class ApplicationMailDeliveryJob < ActionMailer::MailDeliveryJob
  prepend AccountTenanted
end
