# Which of this site's readers the platform won't let it mail, and why —
# domain-admin only, read-only (ADR 0027). The rows are the cross-site
# Suppression ledger filtered two ways: in force for this site (global rows
# and this site's own, minus lifts), and belonging to someone on this site's
# list. A suppression that only names another site is never shown here.
class Admin::SuppressionsController < Admin::BaseController
  def index
    @suppressions = Suppression.in_force_for(Current.account)
      .where(person_id: Current.account.subscribers.select(:person_id))
      .includes(:person).order(created_at: :desc)
  end
end
