# One-off importer: Jekyll `_posts/*.md` → Inkwell published Posts.
#
#   bin/rails 'blog:import[/home/bwilson/Work/merovex.press/_posts]'   # real run
#   DRY_RUN=1 bin/rails 'blog:import[/home/bwilson/Work/merovex.press/_posts]'  # preview
#
# Maps front matter: title→title, date→published_at, summary→excerpt (≤160),
# author→Inkwell Author byline (created from ../_authors if missing). The record
# creator is the first domain admin. `categories` is ignored (Posts have none).
# Idempotent: skips a post whose title already exists, so re-runs are safe.
require "kramdown"
require "kramdown-parser-gfm"
require "cgi"

namespace :blog do
  desc "Import Jekyll _posts markdown into Inkwell. Arg: path to _posts. DRY_RUN=1 to preview."
  task :import, [:posts_path] => :environment do |_t, args|
    posts_path = args[:posts_path].to_s
    abort "Usage: bin/rails 'blog:import[/path/to/_posts]'" if posts_path.blank?
    abort "Not a directory: #{posts_path}" unless File.directory?(posts_path)

    dry = ENV["DRY_RUN"].present?
    creator = User.domain_admin.order(:id).first
    abort "No domain_admin user to own the imported records." unless creator
    site_root = File.dirname(File.expand_path(posts_path))

    puts(dry ? "== DRY RUN — no writes ==" : "== IMPORTING ==")
    puts "Creator: #{creator.email_address}   Site: #{site_root}"

    # Authors: build author_key => Inkwell Author, creating from ../_authors/*.md.
    # author_names keeps the intended byline visible even in a dry run.
    authors = {}
    author_names = {}
    Dir.glob(File.join(site_root, "_authors", "*.md")).sort.each do |file|
      fm, body = BlogImport.split_front_matter(File.read(file))
      key  = (fm["author_key"] || File.basename(file, ".*")).to_s
      name = fm["title"].presence || key
      author_names[key] = name
      authors[key] = BlogImport.upsert_author(name, body, creator, dry:)
    end
    default_key = "ben-wilson"   # posts with no/unknown author get this byline
    puts "Authors: #{authors.keys.inspect}   default: #{author_names[default_key]}"
    puts

    created = skipped = 0
    Dir.glob(File.join(posts_path, "*.{md,markdown}")).sort.each do |file|
      fm, body = BlogImport.split_front_matter(File.read(file))
      title = fm["title"].to_s.strip
      if title.blank?
        puts "  SKIP (no title): #{File.basename(file)}"
        next
      end
      published_at = BlogImport.published_at(fm["date"], file)
      excerpt = fm["summary"].to_s.squish.truncate(160)
      author  = authors[fm["author"].to_s] || authors[default_key]
      html    = BlogImport.markdown_to_html(body)

      if Post.where(title: title).exists?
        puts "  skip (exists): #{title}"
        skipped += 1
        next
      end

      byline = author&.name || author_names[fm["author"].to_s] || author_names[default_key] || creator.display_name
      if dry
        puts "  would import: #{published_at&.to_date}  “#{title}”  byline=#{byline}  (#{html.length} chars, excerpt #{excerpt.length})"
        created += 1
        next
      end

      post = Post.new(
        title: title, content: html, excerpt: excerpt.presence,
        status: :published, event: :created, published_at: published_at,
        creator: creator, author_record_id: author&.record_id)
      Record.originate(post)
      puts "  imported: #{published_at.to_date}  “#{title}”  byline=#{byline}"
      created += 1
    end

    puts
    puts "-- #{dry ? 'would import' : 'imported'}: #{created}   skipped: #{skipped} --"
  end

  desc "Import Jekyll _books into Inkwell (+ Series, covers, buy links). DRY_RUN=1 to preview."
  task :import_books, [:books_path] => :environment do |_t, args|
    books_path = args[:books_path].to_s
    abort "Usage: bin/rails 'blog:import_books[/path/to/_books]'" if books_path.blank?
    abort "Not a directory: #{books_path}" unless File.directory?(books_path)

    dry = ENV["DRY_RUN"].present?
    creator = User.domain_admin.order(:id).first
    abort "No domain_admin user to own the records." unless creator
    site_root = File.dirname(File.expand_path(books_path))

    puts(dry ? "== DRY RUN — no writes ==" : "== IMPORTING BOOKS ==")
    puts "Creator: #{creator.email_address}   Site: #{site_root}"
    author_names = BlogImport.author_key_names(site_root)   # author_key => display name
    series_meta  = BlogImport.series_meta(site_root)        # slug => { name, author, description }
    series_cache = {}

    created = skipped = 0
    Dir.glob(File.join(books_path, "*.{md,markdown}")).sort.each do |file|
      stem = File.basename(file, ".*")
      if BlogImport::IGNORE_BOOKS.include?(stem)
        puts "  ignore: #{stem}"
        next
      end
      fm, _body = BlogImport.split_front_matter(File.read(file))
      title = fm["title"].to_s.strip
      if title.blank?
        puts "  SKIP (no title): #{File.basename(file)}"
        next
      end
      amazon_url = fm["amazon_url"].presence || BlogImport::BOOK_URL_OVERRIDES[stem]
      if Book.where(title: title).exists?
        puts "  skip (exists): #{title}"
        skipped += 1
        next
      end

      slug     = fm["series"].to_s
      byline   = author_names[fm["author"].to_s] || creator.display_name
      cover    = BlogImport.resolve_cover(site_root, fm["cover_image"])
      pub_date = BlogImport.to_date(fm["published_date"])

      if dry
        sname = (series_meta[slug] || {})["name"] || slug
        puts "  would import: “#{title}”  byline=#{byline}  series=#{sname}##{fm['series_order']}  " \
             "cover=#{cover ? File.basename(cover) : 'MISSING!'}  buy=#{amazon_url.present? ? 'amazon' : '—'}  pub=#{pub_date}"
        created += 1
        next
      end

      author = BlogImport.author_for(author_names[fm["author"].to_s], creator)
      series = series_cache[slug] ||= BlogImport.find_or_create_series(slug, series_meta[slug], author_names, creator)
      depiction = BlogImport.build_depiction(cover)

      book = Book.new(
        title: title, content: BlogImport.book_body(fm["subtitle"], fm["description"]),
        status: :published, event: :created,
        published_at: Time.current, publication_date: pub_date,
        creator: creator, author_record_id: author&.record_id)
      book.depiction = depiction
      Record.originate(book)

      Distributor.create!(record: book.record, url: amazon_url) if amazon_url.present?
      Installment.create!(series_record: series.record, book_record: book.record, position: fm["series_order"]) if series

      puts "  imported: “#{title}” → #{series&.title}##{fm['series_order']}  #{depiction ? '[cover]' : '[no cover]'}"
      created += 1
    end

    puts
    puts "-- #{dry ? 'would import' : 'imported'}: #{created}   skipped: #{skipped} --"
  end
end

# Namespaced helpers so the .rake file doesn't leak methods onto Object.
module BlogImport
  module_function

  # One-off book import overrides (keyed by filename stem):
  IGNORE_BOOKS = %w[strand-retribution].freeze          # duplicate title — skip
  BOOK_URL_OVERRIDES = {                                 # buy links missing from front matter
    "strand-redemption" => "https://www.amazon.com/Strand-Redemption-Technology-Colonial-America-ebook/dp/B0GMWQ65ZJ"
  }.freeze

  def split_front_matter(text)
    if text =~ /\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m
      [ YAML.safe_load($1, permitted_classes: [ Date, Time ]) || {}, $2 ]
    else
      [ {}, text ]
    end
  end

  def markdown_to_html(md)
    Kramdown::Document.new(md.to_s, input: "GFM", hard_wrap: false).to_html.strip
  end

  # Jekyll date is a Date (YYYY-MM-DD); fall back to the filename prefix. Land at
  # 09:00 in the app zone so the date reads right regardless of UTC offset.
  def published_at(value, file)
    date =
      case value
      when Time, DateTime then return value.in_time_zone
      when Date           then value
      when String         then (Time.zone.parse(value)&.to_date rescue nil)
      end
    date ||= filename_date(file)
    date && Time.zone.local(date.year, date.month, date.day, 9, 0)
  end

  def filename_date(file)
    if File.basename(file) =~ /\A(\d{4})-(\d{2})-(\d{2})-/
      Date.new($1.to_i, $2.to_i, $3.to_i)
    end
  end

  def upsert_author(name, bio_md, creator, dry:)
    if (existing = Author.current.find_by(name: name))
      return existing
    end
    if dry
      puts "  would create Author: #{name}"
      return nil
    end
    # Create the author first, then set the rich-text bio — assigning bio before
    # Record.originate collides with its double-save (unique action_text row).
    author = Author.new(name: name, creator: creator)
    Record.originate(author)
    bio = markdown_to_html(bio_md.to_s.gsub(/\{%.*?%\}/m, "").gsub(/\{\{.*?\}\}/m, ""))
    author.update!(bio: bio) if bio.present?
    puts "  created Author: #{name}"
    author
  end

  # --- books ---

  # author_key => display name, read from ../_authors/*.md (title front matter).
  def author_key_names(site_root)
    Dir.glob(File.join(site_root, "_authors", "*.md")).each_with_object({}) do |file, h|
      fm, _ = split_front_matter(File.read(file))
      key = (fm["author_key"] || File.basename(file, ".*")).to_s
      h[key] = fm["title"].presence || key
    end
  end

  # Find an existing Author by name (created if missing, name only).
  def author_for(name, creator)
    return nil if name.blank?
    Author.current.find_by(name: name) || begin
      a = Author.new(name: name, creator: creator)
      Record.originate(a)
      a
    end
  end

  def series_meta(site_root)
    file = File.join(site_root, "_data", "series.yml")
    File.exist?(file) ? (YAML.safe_load_file(file) || {}) : {}
  end

  # Attach books to an existing Series by name; create one if it's missing.
  def find_or_create_series(slug, meta, author_names, creator)
    meta ||= {}
    name = meta["name"].presence || slug.to_s.tr("-", " ").split.map(&:capitalize).join(" ")
    existing = Series.current.find_by(title: name)
    return existing if existing

    author = author_for(author_names[meta["author"].to_s], creator)
    series = Series.new(title: name, content: markdown_to_html(meta["description"].to_s),
      status: :published, event: :created, published_at: Time.current,
      creator: creator, author_record_id: author&.record_id)
    Record.originate(series)
    puts "  created Series: #{name}"
    series
  end

  # Resolve a Jekyll cover path (/assets/…) against the site root; nil if absent.
  def resolve_cover(site_root, path)
    return nil if path.blank?
    file = File.join(site_root, path.to_s.sub(%r{\A/}, ""))
    File.exist?(file) ? file : nil
  end

  def build_depiction(cover)
    return nil unless cover
    d = Depiction.new
    d.image.attach(io: File.open(cover, "rb"), filename: File.basename(cover))
    d.save!
    d
  end

  # Book blurb: the subtitle as an emphasized lead line, then the description.
  def book_body(subtitle, description)
    parts = []
    parts << "<p><em>#{CGI.escapeHTML(subtitle.to_s)}</em></p>" if subtitle.present?
    parts << markdown_to_html(description.to_s)
    parts.join("\n")
  end

  def to_date(value)
    case value
    when Date then value
    when Time, DateTime then value.to_date
    when String then (Date.parse(value) rescue nil)
    end
  end
end
