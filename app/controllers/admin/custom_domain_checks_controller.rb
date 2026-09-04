# The "Waiting for DNS" badge's retry (shared/check_badge): create runs the
# status poll inline so the author gets an immediate answer — the background
# poll's re-enqueue chain runs out roughly a day after connect, but DNS lands
# on the author's clock. Running it at attempt 1 also resumes the watch on
# rows the chain gave up on (CustomDomainStatusJob#resume), which is what the
# "Check again" label promises.
#
# When the poll doesn't flip the row, the answer says *why* rather than
# "still waiting": CustomDomain::Diagnosis reads public DNS and names the
# first unmet precondition, so one press is a diagnosis instead of a spinner.
class Admin::CustomDomainChecksController < Admin::BaseController
  def create
    CustomDomainStatusJob.perform_now(Current.account)

    connected = Current.account.custom_domains.connected
    # Canonical first: when both the apex and its www are stuck, the apex is
    # the one the author cares about.
    stuck = connected.where.not(status: "live").order(canonical: :desc).first

    redirect_to admin_custom_domains_path, notice: outcome(connected, stuck)
  end

  private
    def outcome(connected, stuck)
      if stuck then stuck.diagnosis.message
      elsif connected.any? then "Your domain is live."
      else "No domain connected yet."
      end
    end
end
