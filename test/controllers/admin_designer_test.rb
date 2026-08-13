require "test_helper"

# The SiteDesigner (ADR 0022): the two-pane editor with its rail generated
# from the theme manifest, and the stateless preview that builds a posted
# design against real content through the exporter + Hugo pipeline.
class AdminDesignerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # The preview page's markup minus the <head> — the theme inlines its whole
  # stylesheet there, so fk-* class assertions must not grep the CSS.
  def page_markup = response.body.split("</head>", 2).last

  test "the designer is admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_designer_path
    assert_response :not_found
  end

  test "the designer degrades to a 503 notice when the theme manifest is missing" do
    sign_in_as users(:admin)

    # Production without a provisioned theme (THEME_PATH unset → missing tree):
    # the rail can't be built, so the page must not 500 in Theme#axes.
    original = Theme.method(:current)
    Theme.define_singleton_method(:current) { new("/nonexistent-theme-path") }
    begin
      get admin_designer_path
    ensure
      Theme.singleton_class.send(:define_method, :current, original)
    end

    assert_response :service_unavailable
    assert_match(/isn.t available/, response.body)
  end

  test "the rail is generated from the theme manifest" do
    sign_in_as users(:admin)

    get admin_designer_path
    assert_response :success

    theme = Theme.current
    # books + catalog + alternate + hero_book + hero_many + hero_shadow + the
    # author-grid toggle (authors) + the chrome toggles (nav_show,
    # footer_show, footer_signup, footer_credit) + the two home-visibility
    # axes (hero_home, bio_home) + the section-heading toggles (books_title,
    # authors_title, blog_title) + the bio About button (bio_more) render as
    # switches; hero_scrim (manifest control: "slider") as a slider — not
    # fieldsets. hero_art is a 3-way choice, so it renders as an option-card
    # fieldset like the other multi-value axes.
    sliders = theme.axes.count { it["control"] == "slider" }
    assert_select ".designer__axis", count: theme.axes.size - 17 - sliders
    assert_select ".switch__input[data-designer-target=axisToggle]", count: 17
    assert_select ".switch__input[data-axis=hero_home]", count: 1
    assert_select ".switch__input[data-axis=bio_home]", count: 1
    assert_select ".switch__input[data-axis=hero_shadow]", count: 1
    assert_select ".design-option__input[name='design[hero_art]']", count: 3
    assert_select ".switch__input[data-axis=authors]", count: 1
    assert_select ".designer__range[data-axis=hero_scrim]", count: 1
    # Buttons and cover corners render as depiction cards (manifest
    # `depiction`), not sliders.
    assert_select ".design-option__input[name='design[buttons]']", count: 4
    assert_select ".design-option__input[name='design[corners]']", count: 4
    assert_select ".design-option__depiction", count: 13
    assert_select ".design-option__input[name='design[palette]']",
      count: theme.axes.find { it["key"] == "palette" }["options"].size
    # Preset cards: swatch dots + name/tagline in the preset's own faces,
    # grouped under the genre headings.
    assert_select ".designer__preset", count: theme.presets.size
    assert_select ".designer__preset .designer__preset-tagline", count: theme.presets.size

    # Root menu + one sub-pane per style axis, page section, hero, preset,
    # and footer — grouping comes from the manifest's per-axis `section`.
    # Nested-axis sections ride inside another axis's pane, no pane of
    # their own: "palette" (mode) in Palette, "buttons" (second button,
    # size) in Buttons, "nav" (shown) in Header; section "footer" axes all
    # ride the hand-built footer pane.
    sections = theme.axes.map { it["section"] }.uniq
    styles = theme.axes.count { it["section"] == "styles" }
    assert_select ".designer__pane", count: 3 + styles + (sections - %w[styles palette buttons nav footer]).size
    # The Page sections rows ARE the order (drag handles, no order pane);
    # the header row and footer placeholder sit pinned outside the list.
    assert_select "[data-designer-target=orderList] .designer__row--sortable", count: 5
    assert_select ".designer__row--sortable .designer__row-handle", count: 5
    assert_select ".designer__row[data-designer-pane-param=preset]", count: 1

    # Options carrying a manifest wireframe render as inlined-SVG cards.
    wireframed = theme.axes.sum { |axis| axis["options"].count { it["wireframe"] } }
    assert_select ".design-option--card svg", count: wireframed
    # Font pairings render as cards set in their actual faces (name in the
    # heading face, specimen sentence in the body face), plus the hidden
    # custom-pairing memory card (revealed client-side once the author has
    # picked custom fonts).
    font_options = theme.axes.find { it["key"] == "font" }["options"].size
    assert_select ".design-option--font .design-option__font-specimen", count: font_options + 1
    assert_select ".design-option__input[data-custom-font][name='design[font]']", count: 1
    # The header-content editors ride the nav pane as standard modals.
    assert_select "dialog.modal .designer__links", count: 1
    assert_select "dialog.modal [data-designer-target=buttonLabel]", count: 1
    # The hero pane carries the element editor (headline / intro / featured
    # book) and the root menu's featured card shows the variant wireframes.
    assert_select "[data-designer-target=heroHeadline]", count: 1
    assert_select "select[data-designer-target=heroBook]", count: 1
    hero_options = theme.axes.find { it["key"] == "hero" }["options"].size
    assert_select ".designer__featured-thumb[data-chip-for=hero] svg", count: hero_options
    # The canvas bar carries the preview-only Light/Dark peek; the top bar
    # carries the Help modal.
    assert_select ".designer__preview-mode", count: 2
    assert_select "dialog.designer__help", count: 1
  end

  test "the preview carries the posted header links and button through the build" do
    skip_unless_buildable
    sign_in_as users(:admin)

    post admin_designer_preview_path, params: {
      design: { nav: "bare" },
      nav: {
        links: [
          { id: "books", label: "Tomes", visible: true },
          { id: "posts", label: "Posts", visible: false },
          { id: "custom-1", label: "Patreon", url: "https://patreon.com/example", visible: true }
        ],
        button: { label: "Hire me", url: "https://example.com", new_tab: true }
      }
    }, as: :json
    assert_response :no_content

    get admin_designer_preview_file_path(path: nil)
    assert_response :success
    assert_match(/data-nav="?bare"?[ >]/, response.body)
    assert_match(/>Tomes</, response.body)
    assert_no_match(/>Posts</, response.body)
    assert_match(%r{https://patreon\.com/example}, response.body)
    assert_match(/>Hire me</, response.body)
    assert_match(/target="?_blank"?/, response.body)

    # button.visible false removes the CTA entirely (no newsletter fallback).
    post admin_designer_preview_path, params: { design: {}, nav: { button: { visible: false } } }, as: :json
    get admin_designer_preview_file_path(path: nil)
    assert_no_match(/fk-nav-cta/, page_markup)
  end

  test "the preview builds the posted design against published content" do
    skip_unless_buildable
    sign_in_as users(:admin)

    post admin_designer_preview_path, params: { design: { palette: "grimoire", hero: "centered" } }, as: :json
    assert_response :no_content

    # The carousel layout ships the theme's one reader script; the preview
    # server must serve JS (forgery protection 422s controller-served JS
    # on plain GETs unless skipped).
    post admin_designer_preview_path, params: { design: { cards: "carousel" } }, as: :json
    get admin_designer_preview_file_path(path: "assets/js/carousel.js")
    assert_response :success
    assert_match(/pointerdown/, response.body)

    post admin_designer_preview_path, params: { design: { palette: "grimoire", hero: "centered", buttons: "round" } }, as: :json
    get admin_designer_preview_file_path(path: nil)
    assert_response :success
    # --minify strips attribute quotes, so match them optionally.
    assert_match(/data-palette="?grimoire"?[ >]/, response.body)
    assert_match(/data-hero="?centered"?[ >]/, response.body)
    assert_match(/data-buttons="?round"?[ >]/, response.body)

    # The blog axis: home post cards as a vertical list.
    post admin_designer_preview_path, params: { design: { blog: "list" } }, as: :json
    get admin_designer_preview_file_path(path: nil)
    assert_match(/data-blog="?list"?[ >]/, response.body)

    # The hero's orthogonal axes: structure × book rendering × backdrop.
    post admin_designer_preview_path,
      params: { design: { hero: "many", hero_book: "3d", hero_many: "staggered", hero_bg: "banner", hero_scrim: "80" } }, as: :json
    assert_response :no_content
    get admin_designer_preview_file_path(path: nil)
    assert_match(/data-hero-book="?3d"?[ >]/, response.body)
    assert_match(/data-hero-many="?staggered"?[ >]/, response.body)
    assert_match(/data-hero-bg="?banner"?[ >]/, response.body)
    assert_match(/data-hero-scrim="?80"?[ >]/, response.body)
    # Unspecified axes fall back to the manifest defaults.
    assert_match(/data-cards="?#{Theme.current.defaults.fetch("cards")}"?[ >]/, response.body)
  end

  test "the books axis removes the section from the home page" do
    skip_unless_buildable
    sign_in_as users(:admin)

    # Default (yes): the section and its series JSON-LD are on the page.
    post admin_designer_preview_path, params: { design: {} }, as: :json
    assert_response :no_content
    get admin_designer_preview_file_path(path: nil)
    assert_match(/fk-books/, response.body)
    assert_match(/Series by/, response.body)

    post admin_designer_preview_path, params: { design: { books: "no" } }, as: :json
    assert_response :no_content
    get admin_designer_preview_file_path(path: nil)
    assert_match(/data-books="?no"?[ >]/, response.body)
    assert_no_match(/fk-books/, page_markup)
    assert_no_match(/Series by/, page_markup)
    # Only home visibility toggles: the Books nav link (and the books/series
    # pages behind it) stay.
    assert_match(%r{books/"?>Books<}, response.body)

    # Hero and Biography carry the same home-visibility axes.
    post admin_designer_preview_path, params: { design: { hero_home: "no", bio_home: "no" } }, as: :json
    assert_response :no_content
    get admin_designer_preview_file_path(path: nil)
    assert_no_match(/fk-hero /, page_markup)
    assert_no_match(/fk-author-band/, page_markup)
    assert_match(/fk-books/, page_markup)
  end

  test "the hero copy source picks what the hero says" do
    skip_unless_buildable
    sign_in_as users(:admin)

    # Default (author): the author's name leads the headline; the kicker
    # drops its author span and shows the site name solo.
    post admin_designer_preview_path, params: { design: {}, hero: nil }, as: :json
    get admin_designer_preview_file_path(path: nil)
    assert_match(%r{fk-hero-h-title"?>Alice Example<}, response.body)
    assert_match(/fk-kicker-solo/, response.body)

    # Custom: the author's own words — the rich lede is sanitized on every
    # build (prose allowlist; script never reaches the contract), and an
    # unknown book slug falls back to the newest release rather than
    # failing the build.
    post admin_designer_preview_path, params: {
      design: {},
      hero: { source: "custom", headline: "Steel and Static",
              lede_html: "<p>Forgotten marines, <strong>unforgotten</strong> grudges.</p><script>alert(1)</script>",
              book: "no-such-book" }
    }, as: :json
    assert_response :no_content
    get admin_designer_preview_file_path(path: nil)
    assert_match(/Steel and Static/, response.body)
    assert_match(%r{<strong>unforgotten</strong>}, response.body)
    assert_no_match(/alert\(1\)/, response.body)

    # Featured with no published books: falls back to author copy.
    post admin_designer_preview_path, params: { design: {}, hero: { source: "featured" } }, as: :json
    get admin_designer_preview_file_path(path: nil)
    assert_match(%r{fk-hero-h-title"?>Alice Example<}, response.body)

    post admin_designer_preview_path, params: { design: {}, hero: { source: "evil" } }, as: :json
    assert_response :unprocessable_entity
    assert_match(/not a hero copy source/, response.parsed_body["error"])
  end

  test "the newsletter band takes an icon presentation and custom copy" do
    skip_unless_buildable
    sign_in_as users(:admin)

    post admin_designer_preview_path, params: {
      design: { newsletter: "envelope" },
      newsletter: { headline: "Get a free book", blurb: "Join and the first Postal Marines story is yours.", button_label: "Send my copy" }
    }, as: :json
    assert_response :no_content

    get admin_designer_preview_file_path(path: nil)
    assert_response :success
    assert_match(/data-newsletter="?envelope"?[ >]/, response.body)
    assert_match(/fk-newsletter-icon-envelope/, response.body)
    assert_match(/Get a free book/, response.body)
    assert_match(/Send my copy/, response.body)

    # Absent block: the fed defaults keep the band from rendering empty.
    post admin_designer_preview_path, params: { design: {} }, as: :json
    get admin_designer_preview_file_path(path: nil)
    assert_match(/Get new-release updates/, response.body)
    assert_match(/Join the list/, response.body)
  end

  test "the headings block rewords the home bands; absent keeps the defaults" do
    skip_unless_buildable
    sign_in_as users(:admin)

    post admin_designer_preview_path, params: {
      design: {},
      headings: { posts: "Field Notes", books: "The Library" }
    }, as: :json
    assert_response :no_content

    get admin_designer_preview_file_path(path: nil)
    assert_response :success
    assert_match(/Field Notes/, response.body)
    assert_match(/The Library/, response.body)

    # Absent block: the theme's own headings stand.
    post admin_designer_preview_path, params: { design: {} }, as: :json
    get admin_designer_preview_file_path(path: nil)
    assert_match(/From the Blog/, response.body)
    assert_match(/The Books/, response.body)
  end

  test "the section order reorders the home page and must be a permutation" do
    skip_unless_buildable
    sign_in_as users(:admin)

    post admin_designer_preview_path,
      params: { design: {}, sections: %w[bio hero books posts authors newsletter] }, as: :json
    assert_response :no_content
    get admin_designer_preview_file_path(path: nil)
    assert_operator page_markup.index("fk-author-band"), :<, page_markup.index("fk-hero "),
      "biography should render before the hero"

    # Dropping a section through the order block is refused — visibility
    # belongs to each section's own axis.
    post admin_designer_preview_path, params: { design: {}, sections: %w[hero books] }, as: :json
    assert_response :unprocessable_entity
    assert_match(/ordering of/, response.parsed_body["error"])
  end

  test "saving graduates the design to the account and validates like the preview" do
    sign_in_as users(:admin)

    patch admin_designer_path,
      params: { design: { palette: "pine", font: "verse" }, fonts: { display: "Lobster" },
                colors: { bg: "#0ea5e9", accent: "#f59e0b", ink: "#dc2626" },
                hero: { banner_credit: "Photo by Jane Doe on Unsplash",
                        banner_credit_url: "https://unsplash.com/@janedoe" },
                headings: { posts: "Field Notes", books: "" } }, as: :json
    assert_response :no_content

    saved = accounts(:merovex).draft_design.reload.data
    assert_equal "pine", saved["design"]["palette"]
    assert_equal "Lobster", saved["fonts"]["display"]
    assert_equal "Photo by Jane Doe on Unsplash", saved["hero"]["banner_credit"]
    assert_equal "https://unsplash.com/@janedoe", saved["hero"]["banner_credit_url"]
    # Headings ride the bundle override-only: blanks drop out.
    assert_equal({ "posts" => "Field Notes" }, saved["headings"])
    # Colors are stored RAW — the exporter resolves them per build.
    assert_equal "#0ea5e9", saved["colors"]["bg"]

    # Same gates as the preview: an unknown axis value is refused, and a bad
    # save leaves the previously-saved design untouched.
    patch admin_designer_path, params: { design: { palette: "vantablack" } }, as: :json
    assert_response :unprocessable_entity
    assert_match(/not in theme/, response.parsed_body["error"])
    assert_equal "pine", accounts(:merovex).draft_design.reload.data["design"]["palette"]
  end

  test "an unknown design value fails the build loudly" do
    skip_unless_buildable
    sign_in_as users(:admin)

    post admin_designer_preview_path, params: { design: { palette: "vantablack" } }, as: :json
    assert_response :unprocessable_entity
    assert_match(/not in theme/, response.parsed_body["error"])
  end

  test "the preview server refuses paths outside the build root" do
    sign_in_as users(:admin)

    get admin_designer_preview_file_path(path: "../../../config/master.key")
    assert_response :not_found
  end

  test "custom fonts override the pairing in the build; unknown families are refused" do
    skip_unless_buildable
    sign_in_as users(:admin)

    # A space-containing family guards the URL encoding: hand-encoded "+"
    # gets double-escaped by Hugo into a literal %2b, 400ing the whole
    # Google stylesheet.
    post admin_designer_preview_path, params: { design: {}, fonts: { display: "Lobster", body: "Comic Neue" } }, as: :json
    assert_response :no_content

    get admin_designer_preview_file_path(path: nil)
    assert_match(/--font-display:'?Lobster'?/, response.body.gsub(" ", ""))
    assert_match(/family=Lobster/, response.body)
    assert_match(/family=Comic%20Neue/, response.body)
    assert_no_match(/%2b/i, response.body)
    # A custom display face neutralizes the pairing's display personality
    # (weight/tracking/transform), so e.g. noir's uppercase doesn't leak in.
    assert_match(/--display-transform:none/, response.body.gsub(" ", ""))
    assert_match(/--display-weight:400/, response.body.gsub(" ", ""))

    # Family names are interpolated into the theme's head — only exact
    # names from the vendored list may pass.
    post admin_designer_preview_path, params: { design: {}, fonts: { display: "evil'); } </style><script>" } }, as: :json
    assert_response :unprocessable_entity
    assert_match(/not a known Google Font/, response.parsed_body["error"])
  end

  test "custom colors derive a dual-mode palette with our lightness policy; bad input is refused" do
    skip_unless_buildable
    sign_in_as users(:admin)

    post admin_designer_preview_path,
      params: { design: {}, colors: { bg: "#0ea5e9", accent: "#f59e0b", ink: "#dc2626" } }, as: :json
    assert_response :no_content

    get admin_designer_preview_file_path(path: nil)
    body = response.body.gsub(" ", "")
    # The picks' hue survives but WE drive the lightness: whatever the
    # author submitted, light bg is near-white and dark bg near-black.
    %w[bg accent ink].each { |role| assert_match(/--#{role}:light-dark\(#\h{6},#\h{6}\)/, body) }
    light_bg = body[/--bg:light-dark\((#\h{6})/, 1]
    dark_bg = body[/--bg:light-dark\(#\h{6},(#\h{6})/, 1]
    luma = ->(hex) { r, g, b = hex.delete("#").scan(/../).map { it.to_i(16) }; (0.299 * r + 0.587 * g + 0.114 * b) / 255 }
    assert_operator luma.call(light_bg), :>, 0.9, "light bg must be near-white (got #{light_bg})"
    assert_operator luma.call(dark_bg), :<, 0.2, "dark bg must be near-black (got #{dark_bg})"

    # Output hexes are regenerated, never interpolated — and only #rrggbb
    # gets in at all.
    post admin_designer_preview_path,
      params: { design: {}, colors: { bg: "evil;}</style>", accent: "#f59e0b", ink: "#dc2626" } }, as: :json
    assert_response :unprocessable_entity
    assert_match(/not a #rrggbb color/, response.parsed_body["error"])
  end

  test "a non-hash nav payload is ignored, not a crash" do
    skip_unless_buildable
    sign_in_as users(:admin)

    # Stale designer state once sent the nav AXIS value here (a string).
    post admin_designer_preview_path, params: { design: { nav: "split" }, nav: "split" }, as: :json
    assert_response :no_content
  end

  test "a logo upload persists to the Site and rides the preview build" do
    skip_unless_buildable
    sign_in_as users(:admin)

    patch admin_designer_image_path(slot: :logo), params: { logo: fixture_file_upload("avatar.png", "image/png") }
    assert_response :success
    assert accounts(:merovex).site.logo.attached?

    post admin_designer_preview_path, params: { design: {} }, as: :json
    assert_response :no_content
    get admin_designer_preview_file_path(path: nil)
    # The logo replaces the wordmark; the site title survives as its alt.
    assert_match(/fk-brand-logo/, page_markup)
    assert_match(/alt="?Merovex Press"?/, page_markup)
    assert_no_match(/fk-brand-name/, page_markup)

    # title_as_alt: false shows the title beside the logo, alt empties.
    post admin_designer_preview_path, params: { design: {}, nav: { title_as_alt: false } }, as: :json
    get admin_designer_preview_file_path(path: nil)
    assert_match(/fk-brand-name"?>Merovex Press</, page_markup)
    assert_match(/fk-brand-lockup/, page_markup)

    delete admin_designer_image_path(slot: :logo)
    assert_response :no_content
    assert_not accounts(:merovex).site.reload.logo.attached?
  end

  test "a banner upload persists to the Site and rides the preview build" do
    skip_unless_buildable
    sign_in_as users(:admin)

    patch admin_designer_image_path(slot: :banner), params: { banner: fixture_file_upload("avatar.png", "image/png") }
    assert_response :success
    assert accounts(:merovex).site.banner.attached?

    post admin_designer_preview_path, params: { design: { hero_bg: "banner" } }, as: :json
    assert_response :no_content
    get admin_designer_preview_file_path(path: nil)
    assert_match(/data-hero-bg="?banner"?[ >]/, response.body)
    assert_match(/fk-hero-bg-banner/, response.body)

    delete admin_designer_image_path(slot: :banner)
    assert_response :no_content
    assert_not accounts(:merovex).site.reload.banner.attached?

    # The signup band's own backdrop rides the same slot mechanism.
    patch admin_designer_image_path(slot: :newsletter_photo),
      params: { newsletter_photo: fixture_file_upload("avatar.png", "image/png") }
    assert_response :success
    assert accounts(:merovex).site.reload.newsletter_photo.attached?
    post admin_designer_preview_path, params: { design: { newsletter: "photo" } }, as: :json
    get admin_designer_preview_file_path(path: nil)
    assert_match(%r{images/newsletter-}, response.body)
    delete admin_designer_image_path(slot: :newsletter_photo)

    # Only the allowlisted slots exist.
    patch admin_designer_image_path(slot: :evil), params: { evil: fixture_file_upload("avatar.png", "image/png") }
    assert_response :not_found
  end

  test "a bad logo upload reports the validation error" do
    sign_in_as users(:admin)

    patch admin_designer_image_path(slot: :logo), params: { logo: fixture_file_upload("avatar.txt", "text/plain") }
    assert_response :unprocessable_entity
    assert_match(/logo/i, response.parsed_body["error"])
  end

  test "the theme-watch version endpoint is development-only" do
    sign_in_as users(:admin)

    get admin_designer_preview_version_path
    assert_response :not_found
  end

  test "deploying to preview enqueues a preview build and touches no production build" do
    sign_in_as users(:admin)

    assert_enqueued_with(job: PreviewBuildJob, args: [ accounts(:merovex) ]) do
      assert_no_enqueued_jobs(only: SiteBuildJob) do
        post admin_designer_preview_deployment_path
      end
    end
    assert_response :no_content
  end

  test "publishing promotes the draft and schedules the production build" do
    sign_in_as users(:admin)
    accounts(:merovex).draft_design.update!(data: { "design" => { "palette" => "pine" } })

    assert_enqueued_with(job: SiteBuildJob, args: [ accounts(:merovex) ]) do
      post admin_designer_publication_path
    end
    assert_response :no_content
    assert_equal "pine", accounts(:merovex).published_design.data.dig("design", "palette")
  end

  test "the deploy actions are admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    post admin_designer_preview_deployment_path
    assert_response :not_found
    post admin_designer_publication_path
    assert_response :not_found
  end

  private
    # The preview pipeline needs the filibuster checkout (a sibling repo in
    # dev) and the pinned Hugo binary; CI wiring for both is the planned
    # theme sync gate (docs/site-designer.md §2.1).
    def skip_unless_buildable
      skip "filibuster theme not checked out beside the app" unless THEME_PATH.join("data/theme.json").exist?
      skip "hugo binary not available" unless system("#{HUGO_BIN} version", out: File::NULL, err: File::NULL)
    end
end
