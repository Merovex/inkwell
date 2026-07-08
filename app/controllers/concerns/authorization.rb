# Wires the app/policies layer into controllers: authorize! enforces a
# privilege (raising if denied), allowed_to? asks the same question in views
# to decide which affordances to draw. A denial renders the same 404 as a
# missing record — what exists is nobody's business but its audience's.
module Authorization
  extend ActiveSupport::Concern

  included do
    rescue_from ApplicationPolicy::NotAuthorizedError, with: :render_not_found
    helper_method :allowed_to?
  end

  private
    def authorize!(subject, to:)
      policy_for(subject).authorize!(to)
    end

    def allowed_to?(privilege, subject)
      policy_for(subject).public_send("#{privilege}?")
    end

    # The policy class comes from the subject: a Record asks RecordPolicy,
    # the Category class itself asks CategoryPolicy (for collection pages
    # with no instance in hand).
    def policy_for(subject)
      policy_class = subject.is_a?(Class) ? subject : subject.class
      "#{policy_class.name}Policy".constantize.new(Current.user, subject)
    end
end
