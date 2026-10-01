# Sends one confirmed import's invitations (SubscriberImport#invite!). Runs
# inside the import's account, like a request would.
class SubscriberImportJob < ApplicationJob
  queue_as :default

  def perform(import)
    Current.with_account(import.account) { import.invite! }
  end
end
