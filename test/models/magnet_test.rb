require "test_helper"

class MagnetTest < ActiveSupport::TestCase
  test "requires a title and at least one file" do
    magnet = Magnet.new

    assert_not magnet.valid?
    assert magnet.errors[:title].any?
    assert_includes magnet.errors[:base], "Attach an EPUB or a PDF"
  end

  test "rejects a file wearing the wrong content type" do
    magnet = Magnet.new(title: "The Bargain")
    magnet.epub.attach(io: StringIO.new("not an epub"), filename: "book.epub", content_type: "text/plain")

    assert_not magnet.valid?
    assert magnet.errors[:epub].any?
  end

  test "formats lists only the attached formats" do
    assert_equal %w[ epub ], new_magnet.formats
    assert_equal %w[ epub pdf ], new_magnet(pdf: true).formats
  end

  test "mints a permanent slug and resolves any spelling of it" do
    magnet = new_magnet

    assert_match Sluggable::SLUG_FORMAT, magnet.slug
    assert_equal magnet, Magnet.find(magnet.to_param)
    assert_equal magnet, Magnet.find(magnet.to_param.downcase)
  end

  test "destroy sweeps grants and both kinds of downloads" do
    magnet = new_magnet
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    magnet.grant_to(subscriber).downloads.create!(format: "epub")
    magnet.downloads.create!(format: "epub")

    magnet.destroy

    assert_equal 0, Grant.count
    assert_equal 0, Download.count
  end

  test "grant_to mints one grant per subscriber and reuses it" do
    magnet = new_magnet
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)

    grant = magnet.grant_to(subscriber)
    assert_equal grant, magnet.grant_to(subscriber)
    assert_equal 1, magnet.grants.count
  end

  private
    def new_magnet(pdf: false)
      Magnet.new(title: "The Bargain").tap do |magnet|
        magnet.epub.attach(io: StringIO.new("epub bytes"), filename: "the-bargain.epub", content_type: "application/epub+zip")
        magnet.pdf.attach(io: StringIO.new("pdf bytes"), filename: "the-bargain.pdf", content_type: "application/pdf") if pdf
        magnet.save!
      end
    end
end
