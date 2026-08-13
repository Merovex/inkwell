# Loads a Demo::SiteSchema payload into the database through the same model
# paths the app itself uses — User, Account.create_with_owner, and
# Record.originate under Current.with_account — so every validation, tenancy
# stamp, and side effect holds exactly as it would for a real author working
# the admin. Cross-references travel as payload keys; any key that doesn't
# resolve raises (the schema's "resolve or fail loudly" contract).
#
# Covers attach from a local directory when one is given (covers_dir/<key>.*),
# falling back to downloading each book's cover_url.
#
#   rails "demo:load[../demo/stevenson.json]"
class Demo::SiteLoader
  class Error < StandardError; end

  def self.load(payload, covers_dir: nil)
    new(payload, covers_dir: covers_dir).load
  end

  def initialize(payload, covers_dir: nil)
    @payload = payload.deep_symbolize_keys
    @covers_dir = covers_dir
    @author_records = {} # authors[].key => Author record_id
    @book_records = {}   # books[].key   => Record
    @shelved = {}        # books[].key   => series title (a book shelves in at most one series)
  end

  def load
    email = @payload.dig(:user, :email_address)
    raise Error, "A user with #{email} already exists — refusing to double-load" if User.with_email_address(email)

    ApplicationRecord.transaction do
      create_user
      create_account
      Current.with_account(@account) do
        create_authors
        create_posts
        create_books
        create_series
        create_collections
      end
    end
    @account
  end

  private
    def create_user
      @user = User.create!(name: @payload.dig(:user, :name),
        email_address: @payload.dig(:user, :email_address))
    end

    def create_account
      @account = Account.create_with_owner(name: @payload.dig(:site, :name), owner: @user)
      raise Error, "Account invalid: #{@account.errors.full_messages.to_sentence}" unless @account.persisted?

      @account.update!(handle: @payload.dig(:site, :handle)) if @payload.dig(:site, :handle)
      @account.site # originate the Site record now, as first admin contact would
    end

    def create_authors
      @payload[:authors].each do |entry|
        author = Author.new(name: entry[:name], tagline: entry[:tagline], bio: entry[:bio],
          default: entry[:default] || false, creator: @user, event: :created)
        Record.originate(author)
        raise Error, "Duplicate author key #{entry[:key].inspect}" if @author_records.key?(entry[:key])
        @author_records[entry[:key]] = author.record_id
      end
      # "The first becomes the site default unless another sets default: true."
      @default_author_record_id =
        @author_records[@payload[:authors].find { |entry| entry[:default] }&.dig(:key)] ||
        @author_records[@payload[:authors].first[:key]]
    end

    def create_posts
      @payload[:posts].each do |entry|
        post = Post.new(title: entry[:title], excerpt: entry[:excerpt],
          author_record_id: author_record_id(entry[:author]),
          pinned_at: (Time.current if entry[:pinned]),
          creator: @user, event: :created,
          **publish_attributes(entry[:status], at: entry[:published_at]))
        post.content = entry[:body]
        Record.originate(post)
      end
    end

    def create_books
      @payload[:books].each do |entry|
        book = Book.new(title: entry[:title], tagline: entry[:tagline],
          publication_date: entry[:publication_date], isbn: entry[:isbn],
          word_count: entry[:word_count],
          author_record_id: author_record_id(entry[:author]),
          pinned_at: (Time.current if entry[:pinned]),
          creator: @user, event: :created,
          **publish_attributes(entry[:status]))
        book.content = entry[:description]
        book.depiction = build_depiction(entry)
        record = Record.originate(book)
        Array(entry[:buy_links]).each { |url| record.distributors.create!(url: url) }
        raise Error, "Duplicate book key #{entry[:key].inspect}" if @book_records.key?(entry[:key])
        @book_records[entry[:key]] = record
      end
    end

    def create_series
      @payload[:series].each do |entry|
        series = Series.new(title: entry[:title], state: entry[:state],
          author_record_id: author_record_id(entry[:author]),
          creator: @user, event: :created,
          **publish_attributes(entry[:status]))
        series.content = entry[:description] if entry[:description]
        record = Record.originate(series)
        shelve(record, entry[:books], series_title: entry[:title])
      end
    end

    def create_collections
      @payload[:collections].each do |entry|
        collection = Collection.new(title: entry[:title], unordered: entry[:unordered] || false,
          author_record_id: author_record_id(entry[:author]),
          creator: @user, event: :created,
          **publish_attributes(entry[:status]))
        collection.content = entry[:description] if entry[:description]
        record = Record.originate(collection)
        shelve(record, entry[:books])
      end
    end

    # Place books in a container in payload order (position 1..n). Passing
    # series_title also enforces the schema's "a book belongs to at most one
    # series" — collections skip that check.
    def shelve(container_record, keys, series_title: nil)
      keys.each_with_index do |key, index|
        book_record = @book_records.fetch(key) { raise Error, "Unknown book key #{key.inspect}" }
        if series_title
          if (other = @shelved[key])
            raise Error, "Book #{key.inspect} is in two series (#{other.inspect} and #{series_title.inspect})"
          end
          @shelved[key] = series_title
        end
        Installment.create!(container_record_id: container_record.id,
          book_record_id: book_record.id, position: index + 1)
      end
    end

    def author_record_id(key)
      return @default_author_record_id if key.nil?
      @author_records.fetch(key) { raise Error, "Unknown author key #{key.inspect}" }
    end

    # The publish regime at birth: published stamps a go-live moment (the
    # payload's back-dated one when given, else now — mirroring the admin's
    # publish-at-create); anything else is a plain draft.
    def publish_attributes(status, at: nil)
      if status == "published"
        { status: "published", published_at: at ? Time.zone.parse(at) : Time.current }
      else
        { status: "drafted" }
      end
    end

    def build_depiction(entry)
      io, filename = cover_source(entry)
      return nil unless io

      Depiction.new.tap do |depiction|
        depiction.image.attach(io: io, filename: filename)
        depiction.save!
      end
    end

    # The local file (covers_dir/<key>.*) when present, else the payload URL.
    def cover_source(entry)
      if @covers_dir && (path = Dir.glob(File.join(@covers_dir, "#{entry[:key]}.*")).first)
        return [ File.open(path), File.basename(path) ]
      end
      return [ nil, nil ] unless entry[:cover_url]

      uri = URI.parse(entry[:cover_url])
      [ uri.open, File.basename(uri.path).presence || "#{entry[:key]}.jpg" ]
    end
end
