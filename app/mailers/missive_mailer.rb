# Mail for the contact form. Both messages are deliberately content-free to
# protect the sending domain's reputation:
#
#   confirmation — sent to the submitter's own address to complete double opt-in.
#     A FIXED template: it carries only the confirm link, never the submitter's
#     name/subject/body. That closes the abuse vector where someone submits a
#     victim's address plus attacker text and makes us email it to them.
#
#   digest — sent to the domain admins, a COUNT only ("you have X new messages")
#     plus a link to /admin/missives. The actual messages are read in the admin
#     UI; replies go from the admin's own mail client, never through this app.
#
# Both route through the transactional identity (ApplicationMailer's default from).
class MissiveMailer < ApplicationMailer
  def confirmation(missive, token)
    setting = Setting.current
    @site_name = setting.site_name
    @confirm_url = confirm_contact_url(token: token)

    options = { to: missive.email_address, subject: "Confirm your message to #{@site_name}" }
    options[:reply_to] = setting.contact_email if setting.contact_email.present?
    mail(options)
  end

  # A once-daily nudge to the admins. `count` is the number of messages confirmed
  # in the last day; `recipients` is the domain admins' addresses. No message
  # content rides along — just the count and a link to the feed.
  def digest(recipients, count)
    @site_name = Setting.current.site_name
    @count = count
    @missives_url = admin_missives_url

    subject = "#{count} new contact #{'message'.pluralize(count)} — #{@site_name}"
    mail(to: recipients, subject: subject)
  end
end
