class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true

  # The tenant this request is for, resolved by AccountHost::Extractor: on the
  # app host from the /{SLUG} path prefix, on a tenant host from the domain.
  # Nil until APP_HOST enforcement is on (single-tenant legacy behavior).
  attribute :account

  def with_account(value, &)
    with(account: value, &)
  end

  def without_account(&)
    with(account: nil, &)
  end

  # True during web requests (set by ApplicationController), where we can serve
  # modern WebP images. Defaults to false (email-safe) because the Action Text
  # blob partial is shared with newsletter mailers — which have no request — and
  # WebP breaks Outlook desktop. See ApplicationHelper#attachment_variation.
  attribute :web_images
end
