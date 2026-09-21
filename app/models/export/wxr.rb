require "builder"

# content → wordpress.xml: a WordPress eXtended RSS (WXR 1.2) feed of the
# posts and pages, the closest thing the blogging world has to a common
# import format (WordPress reads it natively; Ghost and Substack convert from
# it). Books, newsletters, and drips have no WXR shape — they stay in
# content.json.
#
# Inline images: the archive's bodies point at media/… beside them. An
# importer can't see inside a zip, so here they become root-absolute
# (/media/…) — upload the media folder to the new site's root and every
# image resolves.
class Export::Wxr
  STATUSES = { "published" => "publish", "scheduled" => "future", "drafted" => "draft" }.freeze

  def initialize(content)
    @content = content
  end

  def to_xml
    xml = Builder::XmlMarkup.new(indent: 2)
    xml.instruct!
    xml.rss version: "2.0",
      "xmlns:excerpt" => "http://wordpress.org/export/1.2/excerpt/",
      "xmlns:content" => "http://purl.org/rss/1.0/modules/content/",
      "xmlns:dc" => "http://purl.org/dc/elements/1.1/",
      "xmlns:wp" => "http://wordpress.org/export/1.2/" do
      xml.channel do
        xml.title @content[:site][:name]
        xml.link @content[:site][:url]
        xml.description @content[:site][:tagline]
        xml.language "en-US"
        xml.tag! "wp:wxr_version", "1.2"
        bylines.each { |name| author(xml, name) }
        @content[:posts].each { |post| item(xml, post, type: "post", body: post[:body_html]) }
        @content[:pages].each { |page| item(xml, page, type: "page", body: page[:body_html]) }
      end
    end
  end

  private
    def bylines = @content[:posts].filter_map { |post| post[:byline] }.uniq

    def author(xml, name)
      xml.tag! "wp:author" do
        cdata xml, "wp:author_login", name.parameterize
        cdata xml, "wp:author_display_name", name
      end
    end

    def item(xml, entry, type:, body:)
      xml.item do
        xml.title entry[:title]
        xml.link entry[:url] if entry[:url]
        xml.pubDate Time.iso8601(entry[:published_at]).rfc2822 if entry[:published_at]
        cdata xml, "dc:creator", entry[:byline].to_s.parameterize
        cdata xml, "content:encoded", root_absolute(body)
        cdata xml, "excerpt:encoded", entry[:excerpt].to_s
        xml.tag! "wp:post_id", entry[:id]
        xml.tag! "wp:post_date_gmt", wp_time(entry[:published_at] || entry[:created_at])
        xml.tag! "wp:post_name", entry[:slug]
        xml.tag! "wp:status", STATUSES.fetch(entry[:status], "draft")
        xml.tag! "wp:post_type", type
        xml.tag! "wp:is_sticky", entry[:pinned] ? 1 : 0
      end
    end

    def root_absolute(html) = html.to_s.gsub(%(src="media/), %(src="/media/))

    # Written by hand, not xml.cdata!: Builder's indentation would pad the
    # section with newlines, and importers keep that whitespace as part of the
    # value (an author login of "\n  ben\n"). A literal "]]>" in the text
    # would close the section early, so it's split across two.
    def cdata(xml, name, text)
      xml << "<#{name}><![CDATA[#{text.gsub("]]>", "]]]]><![CDATA[>")}]]></#{name}>\n"
    end

    def wp_time(iso) = Time.iso8601(iso).utc.strftime("%Y-%m-%d %H:%M:%S")
end
