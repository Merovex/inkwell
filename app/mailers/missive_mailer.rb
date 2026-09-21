# Mail for the contact form. Both messages are deliberately content-free to
# protect the sending domain's reputation:
#
#   confirmation — sent to the submitter's own address to complete double opt-in.
#     A FIXED template: it carries only the confirm link, never the submitter's
#     name/subject/body. That closes the abuse vector where someone submits a
#     victim's address plus attacker text and makes us email it to them.
#
#   digest — sent to the site's owner, a COUNT only ("you have X new messages")
#     plus a link to /admin/missives. The actual messages are read in the admin
#     UI; replies go from the admin's own mail client, never through this app.
#
# Both route through the transactional identity (ApplicationMailer's default from).
class MissiveMailer < ApplicationMailer
  # Route through the transactional configuration set (bounce/complaint events
  # only, no click rewriting) — the confirm link is a critical action, and the
  # admin digest is operational mail. Mirrors SessionMailer (ADR 0015); without
  # it, SES sends outside the transactional stream. Rides the platform's
  # transactional identity, so it stamps the platform-auth tenant.
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :transactional_config_set),
    tenant_name: "platform-auth"
  }

  def confirmation(missive, token)
    setting = missive.account.site
    @site_name = setting.site_name
    @confirm_url = confirm_contact_url(token: token, **public_url_options(missive.account))

    # No reply_to (ADR 0029): a contact-form submitter is an unverified stranger
    # until this link is clicked, and the author's address shouldn't reach one.
    mail(to: missive.email_address, subject: "Confirm your message to #{@site_name}")
  end

  # A once-daily nudge to one site's owner. `count` is the number of that
  # site's messages confirmed in the last day. No message content rides along
  # — just the count and a link to the feed, which lives on the app host
  # under the site's slug (Account#admin_path).
  def digest(account, count)
    @site_name = account.site.site_name
    @count = count
    @missives_url = admin_missives_url(script_name: "/#{account.slug}", **app_url_options)

    mail to: account.owner.email_address,
      subject: "#{count} new contact #{'message'.pluralize(count)} — #{@site_name}"
  end
end
