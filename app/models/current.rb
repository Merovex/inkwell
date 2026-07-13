class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true

  # True during web requests (set by ApplicationController), where we can serve
  # modern WebP images. Defaults to false (email-safe) because the Action Text
  # blob partial is shared with newsletter mailers — which have no request — and
  # WebP breaks Outlook desktop. See ApplicationHelper#attachment_variation.
  attribute :web_images
end
