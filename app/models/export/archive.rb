# Assembles an author's export and zips it (see Export). The layout:
#
#   index.html, style.css      — start here: the archive as a small website
#   posts/ pages/ books/ series/ collections/ authors/ newsletters/ drips/
#                              — one readable HTML page per item
#   media/                     — every image, original quality
#   content.json               — the complete machine-readable record
#   wordpress.xml              — posts + pages for WordPress/Ghost/Substack
#   subscribers/               — the three CSVs (Export::Roster)
#   README.txt                 — what each file is for
#
# Export::Content walks the account once; the HTML, JSON, and WXR are all
# rendered from that one hash. Built in a tmp workspace that's removed once
# the caller's block has taken the zip.
class Export::Archive
  TEMPLATES = Rails.root.join("app/views/exports/archive")

  # [ folder, content key, body key ] for the one-page-per-item sections.
  SECTIONS = [
    [ "posts", :posts, :body_html ], [ "pages", :pages, :body_html ],
    [ "books", :books, :description_html ], [ "series", :series, :description_html ],
    [ "collections", :collections, :description_html ]
  ].freeze

  def initialize(account)
    @account = account
  end

  # Yields the path of the finished zip; everything is gone after the block.
  def build
    Dir.mktmpdir("export-#{@account.slug}-") do |dir|
      @root = Pathname(dir).join("archive").tap(&:mkpath)
      write_archive
      zip = Pathname(dir).join("archive.zip")
      compress(zip)
      yield zip
    end
  end

  private
    def content
      @content ||= Export::Content.new(@account) { |blob| store(blob) }.to_h
    end

    def write_archive
      write "content.json", JSON.pretty_generate(content)
      write "wordpress.xml", Export::Wxr.new(content).to_xml
      Export::Roster.new(@account).files.each { |name, csv| write "subscribers/#{name}", csv }
      write "style.css", TEMPLATES.join("style.css").read
      write "README.txt", TEMPLATES.join("README.txt").read
      write_pages
      write "index.html", render("index", content: content, index: @index)
    end

    # One HTML page per item; @index collects [ title, path, note ] per
    # section for the front page.
    def write_pages
      @index = {}
      SECTIONS.each do |folder, key, body|
        content[key].each do |item|
          page folder, item[:slug], title: item[:title], facts: facts(item), cover: item[:cover],
            sections: [ [ nil, item[body] ], ([ "Newsletter tip-in", item[:tipin_html] ] if item[:tipin_html].present?) ].compact,
            note: item[:status]
        end
      end
      content[:authors].each do |author|
        page "authors", "#{author[:id]}-#{author[:name].parameterize}", title: author[:name],
          facts: { "Tagline" => author[:tagline] }, cover: author[:avatar], sections: [ [ nil, author[:bio_html] ] ]
      end
      content[:posts].select { |post| post[:newsletter] }.each do |post|
        letter = post[:newsletter]
        page "newsletters", post[:slug], title: post[:title], note: letter[:state].to_s,
          facts: { "Sent" => date(letter[:sent_at]), "Scheduled" => date(letter[:scheduled_at]),
                   "Recipients" => letter[:recipients], "Delivered" => letter[:delivered],
                   "Opened" => letter[:opened], "Clicked" => letter[:clicked] },
          sections: [ [ nil, letter[:body_html] ] ]
      end
      content[:drips].each do |drip|
        page "drips", "#{drip[:id]}-#{drip[:title].parameterize}", title: drip[:title],
          note: drip[:active] ? "active" : "paused", facts: { "Starts when" => drip[:trigger] },
          sections: drip[:drops].map { |drop| [ "Day #{drop[:delay_days]} — #{drop[:subject]}", drop[:body_html] ] }
      end
    end

    def page(folder, slug, title:, facts:, sections:, cover: nil, note: nil)
      path = "#{folder}/#{slug}.html"
      write path, render("entry", title: title, facts: facts.compact_blank, cover: cover, sections: sections)
      (@index[folder] ||= []) << [ title, path, note ]
    end

    def facts(item)
      { "Status" => item[:archived] ? "#{item[:status]} (archived)" : item[:status],
        "By" => item[:byline], "Published" => date(item[:published_at]), "Written" => date(item[:created_at]),
        "Public address" => item[:url], "ISBN" => item[:isbn], "Publication date" => item[:publication_date] }
    end

    def date(iso) = iso && Time.iso8601(iso).to_fs(:long)

    # Pages sit one folder down; the layout's <base href="../"> points every
    # relative URL (style.css, media/…, index.html) back at the archive root.
    def render(template, **locals)
      ApplicationController.render(template: "exports/archive/#{template}", layout: "exports/archive",
        assigns: { site_name: content[:site][:name], base: ("../" unless template == "index") }, locals: locals)
        .gsub(Body::TEMPLATE_ANNOTATION, "")
    end

    # A blob's place in media/ — originals, not the web-sized copies the site
    # serves. Blob id in the name so two photos sharing a filename can't
    # collide; stored once however many bodies use it.
    def store(blob)
      path = "media/#{blob.id}-#{blob.filename.sanitized}"
      target = @root.join(path)
      target.dirname.mkpath
      target.binwrite(blob.download) unless target.exist?
      path
    rescue ActiveStorage::FileNotFoundError => error
      Rails.logger.warn("[export] missing file for blob #{blob.id}: #{error.message}")
      path
    end

    def write(path, body)
      @root.join(path).tap { |file| file.dirname.mkpath }.write(body)
    end

    def compress(zip)
      Zip::File.open(zip.to_s, create: true) do |archive|
        @root.glob("**/*").select(&:file?).sort.each do |file|
          archive.add(file.relative_path_from(@root).to_s, file.to_s)
        end
      end
    end
end
