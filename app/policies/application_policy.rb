# Plain-Ruby authorization (no gem): one policy class per guarded resource,
# one query method per privilege, ending in allow! or deny!(reason) so every
# denial can say why. Controllers enforce via the Authorization concern
# (authorize! / allowed_to?); collections resolve what a user may see
# through the nested Scope.
class ApplicationPolicy
  class NotAuthorizedError < StandardError
    attr_reader :query, :subject, :policy, :reasons

    def initialize(query:, subject:, policy:, reasons: [])
      @query, @subject, @policy, @reasons = query, subject, policy, reasons

      klass = subject.is_a?(Class) ? subject : subject.class
      message = "Not authorized to #{query} this #{klass}"
      message += " (reasons: #{reasons.join(', ')})" if reasons.any? && Rails.env.development?
      super(message)
    end
  end

  attr_reader :user, :subject, :failure_reasons

  def initialize(user, subject)
    @user = user
    @subject = subject
    @failure_reasons = []
  end

  # authorize!(:manage) asks manage? and raises on refusal, carrying the
  # accumulated reasons for the dev log.
  def authorize!(action)
    return true if public_send("#{action}?")

    raise NotAuthorizedError.new(query: action, subject: subject, policy: self.class, reasons: failure_reasons)
  end

  def self.authorize!(user, subject, action)
    new(user, subject).authorize!(action)
  end

  def self.scope_for(user, relation)
    self::Scope.new(user, relation).resolve
  end

  # Collection filtering: what of this relation may the user see? The
  # default is nothing — each policy declares its own Scope.
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.none
    end

    private
      def admin?
        user.domain_admin?
      end
  end

  private
    # Refuse, remembering why — the reason rides on the error in development.
    def deny!(reason)
      failure_reasons << reason
      false
    end

    def allow!
      true
    end

    def admin?
      user.domain_admin?
    end

    def creator?
      subject.respond_to?(:creator) && subject.creator == user
    end
end
