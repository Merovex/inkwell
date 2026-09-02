require "test_helper"

class AccountTenantedTest < ActiveJob::TestCase
  class ProbeJob < ApplicationJob
    cattr_accessor :seen_account

    def perform
      self.class.seen_account = Current.account
    end
  end

  test "a job enqueued under an account performs under it" do
    account = accounts(:merovex)
    Current.with_account(account) { ProbeJob.perform_later }

    perform_enqueued_jobs
    assert_equal account, ProbeJob.seen_account
  end

  test "a job enqueued without an account performs without one" do
    ProbeJob.seen_account = :unset
    Current.without_account do
      ProbeJob.perform_later
      perform_enqueued_jobs
    end
    assert_nil ProbeJob.seen_account
  end
end
