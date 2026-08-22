# The copy a standing page opens with. A brand-new site publishes its About,
# Privacy, and Terms pages from the first minute (Account#seed_pages), so
# "published and empty" would put three blank pages on the public web —
# starter copy is what keeps that from happening.
#
# The templates live in app/views/pages/starters and carry only what is true
# of every site on the platform: the double opt-in newsletter, stored contact
# messages, masked-IP visit counting, preference cookies. That's a deliberate
# choice over generic boilerplate — an author who never edits the page still
# has an honest one. Rendered with the site's own name and contact address so
# it reads as theirs, not as a template.
#
# Not a substitute for legal advice, and the admin composer says so.
class Page::Starter
  SLUGS = %w[ about privacy terms ].freeze

  # The newsletter page is deliberately absent: its signup band already
  # renders headline and blurb defaults from the design, so a starter
  # paragraph above it would just say the same thing twice.
  def self.html_for(slug, account)
    return unless slug.in?(SLUGS)

    ApplicationController.render(
      template: "pages/starters/#{slug}", layout: false,
      locals: { site_name: account.name, contact: contact_for(account) }
    ).gsub(Body::TEMPLATE_ANNOTATION, "").strip
  end

  # An account may not have a contact address yet (it's optional until the
  # author fills it in), so the copy falls back to naming the form rather
  # than leaving a dangling "write to .".
  def self.contact_for(account)
    account.contact_email.presence || "the contact form on this site"
  end
  private_class_method :contact_for
end
