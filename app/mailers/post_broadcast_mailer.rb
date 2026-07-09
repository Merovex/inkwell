# Emails one published post to one subscriber — the newsletter issue. The post's
# public blog page doubles as the "view in browser" archive (HEY World). Carries
# the subscriber's stable unsubscribe token both in the body and as a
# List-Unsubscribe header (RFC 8058 one-click) for deliverability. From/site
# name come from Setting.current.
class PostBroadcastMailer < ApplicationMailer
  def issue(broadcast, subscriber)
    @post = broadcast.post
    setting = Setting.current
    @site_name = setting.site_name
    @web_url = blog_post_url(broadcast.record.to_slug)
    @unsubscribe_url = unsubscribe_newsletter_url(token: subscriber.generate_token_for(:unsubscribe))

    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    options = { to: subscriber.email_address, subject: @post.title }
    options[:from] = setting.contact_email if setting.contact_email.present?
    mail(options)
  end
end
