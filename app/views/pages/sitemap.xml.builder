xml.instruct! :xml, version: "1.0"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  # Static entry points.
  [ root_url, blog_url, books_url, about_url ].each do |loc|
    xml.url { xml.loc loc }
  end
  xml.url { xml.loc privacy_url } if site_settings.privacy_policy.present?
  xml.url { xml.loc terms_url } if site_settings.terms.present?

  @posts.each do |post|
    xml.url do
      xml.loc blog_post_url(post.record.to_slug)
      xml.lastmod post.updated_at.iso8601
    end
  end

  @books.each do |book|
    xml.url do
      xml.loc book_url(book.record.to_slug)
      xml.lastmod book.updated_at.iso8601
    end
  end
end
