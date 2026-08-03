class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true

  # The tenant this request is for, resolved by AccountHost::Extractor: on the
  # app host from the /{SLUG} path prefix, on a tenant host from the domain.
  # Nil until APP_HOST enforcement is on (single-tenant legacy behavior).
  attribute :account

  # The bucket new records are stamped to — set by the namespace that owns the
  # request. Account/admin space leaves it nil and Record falls back to
  # Current.account; circle space sets it to the Circle (see Circles::Base).
  attribute :bucket

  def with_account(value, &)
    with(account: value, &)
  end

  def with_bucket(value, &)
    with(bucket: value, &)
  end

  def without_account(&)
    with(account: nil, &)
  end

  # Deliberate cross-account work (purge sweeps, digests) declares itself so
  # the dev/test tenancy guard lets it through. Greppable by design.
  attribute :allow_unscoped_tenancy

  def allowing_unscoped_tenancy(&)
    with(allow_unscoped_tenancy: true, &)
  end

  # True during web requests (set by ApplicationController), where we can serve
  # modern WebP images. Defaults to false (email-safe) because the Action Text
  # blob partial is shared with newsletter mailers — which have no request — and
  # WebP breaks Outlook desktop. See ApplicationHelper#attachment_variation.
  attribute :web_images
end
