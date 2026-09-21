# Restrict a controller to the current account's people: its members
# (account_users) and whoever administers it (owner, root). The gate for the
# member-level corners of the admin namespace — commenting and boosting —
# which sit outside AdminOnly so a site's team can take part. Without it,
# "signed in" meant "signed in to Kindred Quill": an author from any other
# site could write onto this one's posts. Denial renders the same 404 as a
# missing record.
module AccountMember
  extend ActiveSupport::Concern

  included do
    before_action :require_account_member
  end

  private
    def require_account_member
      render_not_found unless Current.user&.member_of?(Current.account)
    end
end
