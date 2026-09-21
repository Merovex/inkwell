# Builds one requested site export (Export#build!): walk the account, zip it,
# attach it, email the requester. One build per site at a time. Runs inside
# the export's account, like a request would.
class ExportJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(export) { export.account }

  def perform(export)
    Current.with_account(export.account) { export.build! }
  end
end
