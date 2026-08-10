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
    %w[ site.json author.json books.json series.json posts.json ].each do |file|
      assert @workspace.join("data", file).exist?, "missing data/#{file}"
    end
  end

  test "every file carries the contract version" do
    %w[ site author books series posts ].each do |name|
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

  # A published build's assets/nav must resolve at BOTH the canonical domain
  # root and the platform path prefix (sites.kindredquill.com/<handle>/), so
  # the config turns on Hugo's page-relative URLs. The designer preview is
  # served at a fixed non-directory path that matches its base_url, where
  # page-relative URLs resolve one level too high — so preview keeps them off.
  test "hugo.toml enables relative URLs for published builds but not for preview" do
    assert_includes @workspace.join("hugo.toml").read, "relativeURLs = true"

    preview = Exporter.new(accounts(:merovex), base_url: "/admin/theme/preview/", preview: true).export!
    assert_includes preview.join("hugo.toml").read, "relativeURLs = false"
  end

  test "a published build emits page-relative asset URLs; preview emits absolute" do
    skip "hugo binary not available" unless system("#{HUGO_BIN} version", out: File::NULL, err: File::NULL)

    home = Renderer.new(@workspace).render!.join("index.html").read
    assert_includes home, "./assets/css/", "published home links assets relative to the page"
    assert_no_match %r{href=/assets/css/}, home, "no root-absolute asset paths that break under a path prefix"

    preview = Exporter.new(accounts(:merovex), base_url: "/admin/theme/preview/", preview: true).export!
    preview_home = Renderer.new(preview).render!.join("index.html").read
    assert_includes preview_home, "/admin/theme/preview/assets/css/", "preview keeps absolute paths anchored to base_url"
  end

  private
    def data(name)
      JSON.parse(@workspace.join("data", "#{name}.json").read)
    end
end
