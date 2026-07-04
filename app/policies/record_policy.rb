# Who may do what to a record's content. The subject is the Record (the
# stable identity) — the creator lives there, not on the versions.
class RecordPolicy < ApplicationPolicy
  # The write actions: edit, publish, schedule, pin, trash, draft-shredding.
  def manage?
    return allow! if admin? || creator?

    deny! :not_creator
  end

  # Published content belongs to the whole install; unpublished work stays
  # between its creator and the admin. Types with no publish regime
  # (comments, chat lines) are public from their first save.
  def view?
    content = subject.recordable
    return allow! unless content.respond_to?(:published?)
    return allow! if content.published? || manage?

    deny! :unpublished
  end

  # What the drafts pages may list: unpublished work is yours-only; the
  # admin sees everyone's. Takes a Publishable relation (Post, Message) —
  # created_by keys on the record's creator, the identity.
  class Scope < ApplicationPolicy::Scope
    def resolve
      admin? ? scope.all : scope.created_by(user)
    end
  end
end
