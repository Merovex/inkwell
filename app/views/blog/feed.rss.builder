xml.instruct! :xml, version: "1.0"
xml.rss version: "2.0", "xmlns:atom": "http://www.w3.org/2005/Atom" do
  xml.channel do
    xml.title site_settings.site_name
    xml.description site_settings.tagline.presence || "Latest from #{site_settings.site_name}"
    xml.link blog_url
    xml.tag! "atom:link", href: blog_feed_url(format: :rss), rel: "self", type: "application/rss+xml"
    xml.language "en"

    @posts.each do |post|
      url = blog_post_url(post.record.to_slug)
      xml.item do
        xml.title post.title
        xml.description post.content.to_plain_text.to_s.truncate(500)
        xml.pubDate post.published_at.to_fs(:rfc822)
        xml.link url
        xml.guid url, isPermaLink: "true"
        xml.author post.record.creator.display_name
      end
    end
  end
end
