# Serializes the enqueuing request's Current.account into job data and
# restores it around perform, so jobs never infer tenancy (adapted from
# Fizzy). Resolution is deferred to around_perform so a since-deleted account
# raises DeserializationError inside the execution path, where discard_on can
# handle it. Jobs enqueued with no account (cron ticks, sweeps) run
# account-less, exactly as before.
module AccountTenanted
  extend ActiveSupport::Concern

  prepended do
    attr_reader :account
    around_perform :with_account_context
  end

  def initialize(...)
    super
    @account = Current.account
  end

  def serialize
    super.merge({ "account" => @account&.to_gid })
  end

  def deserialize(job_data)
    super
    @account_gid = job_data["account"]
  end

  private
    def with_account_context(&block)
      resolve_account!

      if account.present?
        Current.with_account(account, &block)
      else
        yield
      end
    end

    def resolve_account!
      if @account_gid
        @account = GlobalID::Locator.locate(@account_gid)
      end
    rescue ActiveRecord::RecordNotFound
      raise ActiveJob::DeserializationError
    end
end
