require "test_helper"

# The author's archive (Export::Archive): everything but trash, as HTML to
# read, content.json, wordpress.xml, and the three subscriber CSVs.
class Export::ArchiveTest < ActiveSupport::TestCase
  setup { @account = accounts(:merovex) }

  test "the zip holds the front page, data files, README, and a page per post — drafts included" do
    entries = archive.keys

    %w[ index.html style.css README.txt content.json wordpress.xml
        subscribers/subscribers.csv subscribers/suppressions.csv subscribers/consent_events.csv ].each do |path|
      assert_includes entries, path
    end
    assert_includes entries, "posts/#{slug(:kickoff)}.html"
    assert_includes entries, "posts/#{slug(:typography)}.html", "a draft is the author's work too"
  end

  test "trashed content stays behind" do
    records(:typography).trash

    assert_not_includes archive.keys, "posts/#{slug(:typography)}.html"
    assert_not_includes content["posts"].map { it["title"] }, posts(:typography).title
  end

  test "content.json carries status, and a URL only for what the world can visit" do
    published, draft = content["posts"].partition { it["status"] == "published" }.map(&:first)

    assert_equal "inkwell-export", content["format"]
    assert_equal "https://merovex.press/posts/#{slug(:kickoff)}", published["url"]
    assert_nil draft["url"]
    assert_no_match(/-[0-9a-z]{5}\z/, draft["slug"].delete_prefix(records(:typography).id.to_s),
      "a draft's slug carries no preview key")
  end

  test "item pages resolve relative URLs from the archive root" do
    page = archive.fetch("posts/#{slug(:kickoff)}.html")

    assert_includes page, %(<base href="../">)
    assert_includes page, %(<link rel="stylesheet" href="style.css">)
    assert_includes page, posts(:kickoff).title
    assert_not_includes archive.fetch("index.html"), "<base"
  end

  test "an inline body image lands in media/ at original quality and the body points at it" do
    blob = ActiveStorage::Blob.create_and_upload!(io: file_fixture("avatar.png").open,
      filename: "inline.png", content_type: "image/png")
    records(:kickoff).revise(event: :updated, content:
      %(<p>Look:</p><action-text-attachment sgid="#{blob.attachable_sgid}" content-type="image/png" filename="inline.png"></action-text-attachment>))

    files = archive
    body = JSON.parse(files.fetch("content.json"))["posts"].find { it["id"] == records(:kickoff).id }["body_html"]

    assert_includes body, %(src="media/#{blob.id}-inline.png")
    assert_not_includes body, "action-text-attachment"
    assert_equal blob.download.bytesize, files.fetch("media/#{blob.id}-inline.png").bytesize
    assert_includes files.fetch("wordpress.xml"), %(src="/media/#{blob.id}-inline.png"),
      "WXR images are root-absolute: upload media/ to the new site's root"
  end

  test "wordpress.xml is well-formed WXR with WordPress statuses" do
    xml = Nokogiri::XML(archive.fetch("wordpress.xml")) { |config| config.strict }
    statuses = xml.xpath("//item").to_h { [ it.at_xpath("title").text, it.at_xpath("wp:status").text ] }

    assert_equal "1.2", xml.at_xpath("//wp:wxr_version").text
    assert_equal "publish", statuses[posts(:kickoff).title]
    assert_equal "draft", statuses[posts(:typography).title]
    assert_no_match(/\A\s|\s\z/, xml.at_xpath("//wp:author_login").text, "CDATA values carry no padding")
  end

  test "subscribers are split so the importable list can't mail anyone it shouldn't" do
    reader = subscriber("reader@example.com", status: "confirmed", confirmed_at: 1.day.ago)
    subscriber("gone@example.com", status: "unsubscribed", unsubscribed_at: 1.hour.ago)
    subscriber("bounced@example.com", status: "bounced")
    subscriber("maybe@example.com", status: "pending")
    subscriber("seed@example.com", status: "confirmed", seed: true)
    blocked = subscriber("blocked@example.com", status: "confirmed")
    Suppression.impose!(person: blocked.person, reason: "hard_bounce")
    reader.events.create!(action: "confirmed", ip_address: "203.0.113.9", source: "nav")

    files = archive
    list = CSV.parse(files.fetch("subscribers/subscribers.csv"), headers: true)
    suppressed = CSV.parse(files.fetch("subscribers/suppressions.csv"), headers: true)
    consent = CSV.parse(files.fetch("subscribers/consent_events.csv"), headers: true)

    assert_equal [ "reader@example.com" ], list["email_address"]
    assert_equal({ "blocked@example.com" => "suppressed", "bounced@example.com" => "bounced", "gone@example.com" => "unsubscribed" },
      suppressed.to_h { [ it["email_address"], it["reason"] ] })
    assert_includes consent.map { it.values_at("email_address", "action", "ip_address") },
      [ "reader@example.com", "confirmed", "203.0.113.9" ]
    assert_match(/\A\d{4}-\d{2}-\d{2}T[\d:]+Z\z/, list.first["confirmed_at"], "ISO 8601, UTC")
  end

  test "a formula-shaped signup source is defused in the CSV" do
    subscriber("reader@example.com", status: "confirmed", source: "=HYPERLINK(1)")

    list = CSV.parse(archive.fetch("subscribers/subscribers.csv"), headers: true)
    assert_equal "'=HYPERLINK(1)", list.first["source"]
  end

  private
    # { "path/in/zip" => bytes } for a fresh build.
    def archive
      Export::Archive.new(@account).build do |zip|
        Zip::File.open(zip.to_s) { |file| file.entries.select(&:file?).to_h { [ it.name, it.get_input_stream.read ] } }
      end
    end

    def content = JSON.parse(archive.fetch("content.json"))

    def slug(name) = "#{records(name).id}-#{posts(name).title.parameterize}"

    def subscriber(email, **attributes)
      Subscriber.create!(email_address: email, **attributes)
    end
end
