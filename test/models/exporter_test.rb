require "test_helper"

# The Phase 2 JSON transport (docs/hugo-build-pipeline.md §4): a build
# workspace is a snapshot of "published now" — current versions, published
# only — stamped with the contract version and the default design axes.
class ExporterTest < ActiveSupport::TestCase
  setup do
    @builds_path = Dir.mktmpdir
    ENV["BUILDS_PATH"] = @builds_path
    @workspace = Exporter.new(accounts(:merovex)).export!
  end

  teardown do
    ENV.delete("BUILDS_PATH")
    FileUtils.remove_entry(@builds_path)
  end

  test "the workspace lands under BUILDS_PATH/<account_slug> with every data file" do
    assert_equal accounts(:merovex).slug, @workspace.parent.basename.to_s
    %w[ site.json author.json books.json series.json posts.json pages.json ].each do |file|
      assert @workspace.join("data", file).exist?, "missing data/#{file}"
    end
  end

  test "every file carries the contract version" do
    %w[ site author books series posts pages ].each do |name|
      assert_equal Exporter::CONTRACT_VERSION, data(name)["contract_version"], "#{name}.json"
    end
  end

  test "site.json carries identity and the theme manifest's design defaults" do
    site = data("site")
    assert_equal "Merovex Press", site["name"]
    assert_equal "hello@merovex.press", site["contact_email"]
    assert_equal Theme.current.defaults, site["design"]
  end

  test "posts.json holds published posts only, rendered as HTML" do
    slugs = data("posts")["posts"].map { it["slug"] }
    assert_includes slugs, records(:kickoff).to_slug
    assert_not_includes slugs, records(:typography).to_slug, "drafts must not export"

    kickoff = data("posts")["posts"].find { it["slug"] == records(:kickoff).to_slug }
    assert_equal "Kickoff notes for the winter issue", kickoff["title"]
    assert kickoff["body_html"].present?
  end

  test "author.json falls back to the owner when no persona exists" do
    assert_equal users(:alice).display_name, data("author")["name"]
  end

  test "site.json carries no signup block until the account can send the confirmation" do
    assert_nil data("site").dig("newsletter", "signup")
  end

  test "site.json wires the newsletter signup — with the account's OWN sitekey — once SES is provisioned" do
    accounts(:merovex).update!(ses_tenant_provisioned_at: Time.current, turnstile_site_key: "sk-merovex")
    workspace = Exporter.new(accounts(:merovex).reload).export!

    signup = JSON.parse(workspace.join("data", "site.json").read).dig("newsletter", "signup")
    assert signup["enabled"]
    assert_equal "ses", signup["provider"], "provider picks the theme's form partial"
    assert_equal Subscriber::HONEYPOT_FIELD, signup["honeypot_field"]
    assert_equal "sk-merovex", signup["turnstile_sitekey"]
  end

  test "a provisioned account's built home renders the signup form, honeypot, and widget" do
    skip "hugo binary not available" unless system("#{HUGO_BIN} version", out: File::NULL, err: File::NULL)

    accounts(:merovex).update!(ses_tenant_provisioned_at: Time.current, turnstile_site_key: "sk-merovex")
    workspace = Exporter.new(accounts(:merovex).reload).export!

    destination = Renderer.new(workspace).render!
    home = destination.join("index.html").read
    assert_includes home, "/newsletter", "form posts to the island"
    assert_includes home, %(name=#{Subscriber::HONEYPOT_FIELD}), "pinned honeypot is baked in"
    assert_includes home, "sk-merovex", "Turnstile widget carries the account's sitekey"
    # The band's own mailto fallback yields to the form (the nav/hero "Get
    # updates" CTAs still carry mailto links — a separate partial).
    band = home[/fk-newsletter-band.*/m]
    assert_not_includes band, "mailto:", "the band's mailto fallback yields to the real form"

    # The band is also its own destination — /newsletter was a Rails page
    # pre-cutover, so the static site keeps the URL alive.
    standalone = destination.join("newsletter/index.html").read
    assert_includes standalone, %(name=#{Subscriber::HONEYPOT_FIELD}), "standalone page carries the same form"
  end

  # A ROOT-based build (custom domain) turns on Hugo's page-relative URLs so
  # its assets/nav resolve at BOTH the domain root and the platform path
  # prefix (sites.kindredquill.com/<handle>/). A path-prefixed baseURL
  # (domain-less account) keeps absolute URLs — Hugo relativizes against the
  # output path, so relative + prefix emits a doubled /<handle>/<handle>/
  # that 404s. The designer preview is served at a fixed non-directory path
  # that matches its base_url, where page-relative URLs resolve one level too
  # high — so preview keeps them off regardless.
  test "hugo.toml enables relative URLs for root-based builds only" do
    assert_includes @workspace.join("hugo.toml").read, "relativeURLs = true"

    domain = Exporter.new(accounts(:merovex), base_url: "https://merovex.press/").export!
    assert_includes domain.join("hugo.toml").read, "relativeURLs = true"

    prefixed = Exporter.new(accounts(:merovex), base_url: "https://sites.kindredquill.com/F3WHRQ/").export!
    assert_includes prefixed.join("hugo.toml").read, "relativeURLs = false"

    preview = Exporter.new(accounts(:merovex), base_url: "/admin/theme/preview/", preview: true).export!
    assert_includes preview.join("hugo.toml").read, "relativeURLs = false"
  end

  test "a root-based build emits page-relative asset URLs; prefixed and preview emit absolute" do
    skip "hugo binary not available" unless system("#{HUGO_BIN} version", out: File::NULL, err: File::NULL)

    home = Renderer.new(@workspace).render!.join("index.html").read
    assert_includes home, "./assets/css/", "published home links assets relative to the page"
    assert_no_match %r{href=/assets/css/}, home, "no root-absolute asset paths that break under a path prefix"

    prefixed = Exporter.new(accounts(:merovex), base_url: "https://sites.kindredquill.com/F3WHRQ/").export!
    prefixed_out = Renderer.new(prefixed).render!
    prefixed_home = prefixed_out.join("index.html").read
    assert_includes prefixed_home, "/F3WHRQ/assets/css/", "prefixed build anchors assets to its one home"
    assert_no_match %r{F3WHRQ/F3WHRQ}, prefixed_home, "no doubled prefix (Hugo relativizes against the output path)"
    # Deep pages are where the doubling bit: ../../F3WHRQ/assets from /F3WHRQ/posts/<slug>/.
    post = prefixed_out.join("posts", records(:kickoff).to_slug, "index.html").read
    assert_no_match %r{F3WHRQ/F3WHRQ}, post, "post pages carry no doubled prefix"
    assert_no_match %r{\.\./}, post, "prefixed build has no page-relative URLs at all"

    preview = Exporter.new(accounts(:merovex), base_url: "/admin/theme/preview/", preview: true).export!
    preview_home = Renderer.new(preview).render!.join("index.html").read
    assert_includes preview_home, "/admin/theme/preview/assets/css/", "preview keeps absolute paths anchored to base_url"
  end

  test "pages.json carries the published standing pages, ordered by slug" do
    accounts(:merovex).page("about").record.save_edit(content: "<p>Two names.</p>", creator: users(:alice))
    workspace = Exporter.new(accounts(:merovex)).export!
    pages = JSON.parse(workspace.join("data", "pages.json").read)["pages"]

    assert_equal %w[ about newsletter privacy terms ], pages.map { |page| page["slug"] }
    about = pages.first
    assert_equal "About", about["title"]
    assert_includes about["body_html"], "Two names."
  end

  test "an unpublished page leaves the build entirely" do
    accounts(:merovex).page("terms").unpublish
    workspace = Exporter.new(accounts(:merovex)).export!
    pages = JSON.parse(workspace.join("data", "pages.json").read)["pages"]

    assert_not_includes pages.map { |page| page["slug"] }, "terms"
  end

  test "an inline body image is copied into the build and repointed at the copy" do
    blob = ActiveStorage::Blob.create_and_upload!(io: file_fixture("avatar.png").open,
      filename: "inline.png", content_type: "image/png")
    accounts(:merovex).page("about").record.save_edit(creator: users(:alice), content:
      %(<p>Look:</p><action-text-attachment sgid="#{blob.attachable_sgid}" content-type="image/png" filename="inline.png"></action-text-attachment>))

    workspace = Exporter.new(accounts(:merovex)).export!
    body = JSON.parse(workspace.join("data", "pages.json").read)["pages"]
      .find { |page| page["slug"] == "about" }["body_html"]

    src = body[/src="([^"]+)"/, 1]
    assert_equal "images/inline-#{blob.id}-inline.webp", src
    assert workspace.join("assets", src).exist?, "the blob should be copied into the workspace"
    # Nothing pointing back at Rails, and no custom element left to lay out.
    assert_not_includes body, "active_storage"
    assert_not_includes body, "action-text-attachment"
    # ActionText's filename/size caption is composer chrome, not prose.
    assert_not_includes body, "figcaption"
  end

  private
    def data(name)
      JSON.parse(@workspace.join("data", "#{name}.json").read)
    end
end
