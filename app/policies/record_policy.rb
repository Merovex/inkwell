# Who may do what to a record's content. The subject is the Record (the
# stable identity) — the creator lives there, not on the versions.
class RecordPolicy < ApplicationPolicy
  # The write actions: edit, publish, schedule, pin, trash, draft-shredding.
  def manage?
    return deny! :not_a_member unless member?
    return allow! if admin? || creator?

    deny! :not_creator
  end

  # Published content belongs to the whole SITE — its members and admins,
  # never the whole platform; unpublished work stays between its creator and
  # the admin. Types with no publish regime (comments, chat lines) are
  # visible to the site from their first save.
  def view?
    return deny! :not_a_member unless member?

    content = subject.recordable
    return allow! unless content.respond_to?(:published?)
    return allow! if content.published? || manage?

    deny! :unpublished
  end

  # The tenancy floor under every privilege: a record in a site answers only
  # to that site's people. Keyed on the record's own bucket, not the ambient
  # account, so a policy check can't be fooled by where it's asked from.
  # Records outside account space (circles, platform bulletins) have their
  # own gates and pass through.
  def member?
    !subject.bucket.is_a?(Account) || user.member_of?(subject.bucket)
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
