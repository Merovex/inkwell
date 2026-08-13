# The contract for a demo-site payload: one User owning one Site (Account),
# with its authors, posts, books, series, and collections. Emits a Draft
# 2020-12 JSON Schema (Schematist) — hand it to a generator (human or LLM) to
# produce the payload, then to a loader to build the records. Cross-references
# between sections travel as `key` strings (kebab-case, unique per payload);
# JSON Schema can't enforce them, so the loader must resolve or fail loudly.
#
# `rails demo:schema` prints the document.
class Demo::SiteSchema < Schematist::Schema
  title "DemoSite"
  description "A complete demo site: one user owning one site, with authors, " \
    "posts, books, series, and collections. Content bodies are HTML fragments " \
    "(<p> paragraphs) for the record's rich text."

  KEY_PATTERN = "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$"
  # The publish regime (Publishable): drafts stay private, published is live.
  # Scheduling needs a future timestamp that would go stale in a static
  # payload, so it stays out of the contract.
  STATUSES = %w[ drafted published ].freeze

  object :user do
    description "The demo account owner."

    string :name, pattern: KEY_PATTERN,
      description: "Handle, unique across users (e.g. \"gutenberg\")."
    string :email_address, format: "email"
  end

  object :site do
    description "The Account (site) the user owns; all content below lives in it."

    string :name, description: "Site title (e.g. \"Gutenberg Press\")."
    string :handle, required: false, pattern: KEY_PATTERN,
      description: "Kindred Quill handle for the platform URL and shared-lane " \
        "email From. Omit to leave unclaimed."
  end

  array :authors, min_items: 1 do
    description "Public pen names / bylines. The first becomes the site default " \
      "unless another sets default: true."

    object do
      string :key, pattern: KEY_PATTERN,
        description: "Payload-unique id other sections reference as author:."
      string :name, description: "The byline as shown on the site."
      string :tagline, required: false, max_length: 140,
        description: "One-line hook under the name in the author grid."
      string :bio, required: false, description: "HTML bio for the author page."
      boolean :default, required: false,
        description: "Make this the site's default byline (at most one)."
    end
  end

  array :posts do
    description "Blog posts, oldest first."

    object do
      string :title
      string :author, required: false, pattern: KEY_PATTERN,
        description: "An authors[].key; omit for the site default."
      string :status, enum: STATUSES
      string :published_at, required: false, format: "date-time",
        description: "Back-dated go-live moment for published posts; the loader " \
          "stamps now when omitted. Ignored for drafts."
      string :excerpt, required: false, max_length: 160,
        description: "SEO summary for list rows and the meta description; " \
          "omitted means the body gets truncated instead."
      string :body, description: "HTML body."
      boolean :pinned, required: false, description: "Pin to the top of the blog."
    end
  end

  array :books, min_items: 1 do
    description "The catalog. Series and collections reference these by key."

    object do
      string :key, pattern: KEY_PATTERN,
        description: "Payload-unique id series/collections reference."
      string :title
      string :author, required: false, pattern: KEY_PATTERN,
        description: "An authors[].key; omit for the site default."
      string :tagline, required: false,
        description: "One-line pitch shown under the title."
      string :status, enum: STATUSES
      string :publication_date, required: false, format: "date",
        description: "Real-world release date (distinct from the record going " \
          "live). Give it for published books; omit for unreleased drafts."
      string :isbn, required: false
      integer :word_count, required: false, minimum: 1
      string :description, description: "HTML description for the book page."
      string :cover_url, required: false, format: "uri",
        description: "Cover image the loader downloads and attaches."
      array :buy_links, of: :string, required: false,
        description: "Store URLs; the platform (Amazon, Kobo…) is detected " \
          "from each URL."
      boolean :pinned, required: false, description: "Feature on the shelf."
    end
  end

  array :series do
    description "Ordered runs of books."

    object do
      string :title
      string :author, required: false, pattern: KEY_PATTERN,
        description: "An authors[].key; omit for the site default."
      string :state, enum: %w[ planned in_progress complete ],
        description: "Where the run stands, for the shelf band."
      string :status, enum: STATUSES
      string :description, required: false, description: "HTML description."
      array :books, of: :string, min_items: 1,
        description: "books[].key values in reading order (position 1..n). " \
          "A book belongs to at most one series."
    end
  end

  array :collections do
    description "Curated groupings that cut across series (e.g. \"Where to " \
      "Start\"). Unlike series, a book may appear in many collections."

    object do
      string :title
      string :author, required: false, pattern: KEY_PATTERN,
        description: "An authors[].key; omit for the site default."
      boolean :unordered, required: false,
        description: "True for an unranked grab-bag; false/omitted keeps the " \
          "listed order."
      string :status, enum: STATUSES
      string :description, required: false, description: "HTML description."
      array :books, of: :string, min_items: 1,
        description: "books[].key values."
    end
  end
end
