class ApplicationMailer < ActionMailer::Base
  default from: Rails.application.credentials.dig(:mailgun, :from) || "from@example.com"
  layout "mailer"
end
