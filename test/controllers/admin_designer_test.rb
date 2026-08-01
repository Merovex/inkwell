require "test_helper"

# The SiteDesigner (ADR 0022): the two-pane editor with its rail generated
# from the theme manifest, and the stateless preview that builds a posted
# design against real content through the exporter + Hugo pipeline.
class AdminDesignerTest < ActionDispatch::IntegrationTest
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
    # books + catalog + alternate + hero_book + hero_many + the author-grid
    # toggle (authors) + the two home-visibility axes (hero_home, bio_home)
    # render as switches; corners, buttons, and hero_scrim (manifest control:
    # "slider") as sliders — not fieldsets. hero_art is a 3-way choice, so it
    # renders as an option-card fieldset like the other multi-value axes.
    sliders = theme.axes.count { it["control"] == "slider" }
    assert_select ".designer__axis", count: theme.axes.size - 8 - sliders
    assert_select ".switch__input[data-designer-target=axisToggle]", count: 8
    assert_select ".switch__input[data-axis=hero_home]", count: 1
    assert_select ".switch__input[data-axis=bio_home]", count: 1
    assert_select ".design-option__input[name='design[hero_art]']", count: 3
    assert_select ".switch__input[data-axis=authors]", count: 1
    assert_select ".designer__range[data-axis=hero_scrim]", count: 1
    assert_select ".designer__range[data-axis=corners]", count: 1
    assert_select ".designer__range[data-axis=buttons]", count: 1
    assert_select ".design-option__input[name='design[palette]']",
      count: theme.axes.find { it["key"] == "palette" }["options"].size
    # Preset cards: swatch dots + name/tagline in the preset's own faces,
    # grouped under the genre headings.
    assert_select ".designer__preset", count: theme.presets.size
    assert_select ".designer__preset .designer__preset-tagline", count: theme.presets.size

    # Root menu + one sub-pane per style axis, page section, hero, preset,
    # and the section-order pane — grouping comes from the manifest's
    # per-axis `section`. Section "palette" axes (mode) ride inside the
    # palette pane, no pane of their own.
    sections = theme.axes.map { it["section"] }.uniq
    styles = theme.axes.count { it["section"] == "styles" }
    assert_select ".designer__pane", count: 3 + styles + (sections - %w[styles palette]).size
    assert_select ".designer__order-row", count: 6
    assert_select ".designer__row[data-designer-pane-param=preset]", count: 1

    # Options carrying a manifest wireframe render as inlined-SVG cards.
    wireframed = theme.axes.sum { |axis| axis["options"].count { it["wireframe"] } }
    assert_select ".design-option--card svg", count: wireframed
    # Font pairings render as cards set in their actual faces, plus the
    # hidden custom-pairing memory card (revealed client-side once the
    # author has picked custom fonts).
    font_options = theme.axes.find { it["key"] == "font" }["options"].size
    assert_select ".design-option--font .design-option__font-tagline", count: font_options + 1
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
    assert_no_match(/fk-nav-cta/, response.body)
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
    assert_no_match(/fk-books/, response.body)
    assert_no_match(/Series by/, response.body)
    # Only home visibility toggles: the Books nav link (and the books/series
    # pages behind it) stay.
    assert_match(%r{books/"?>Books<}, response.body)

    # Hero and Biography carry the same home-visibility axes.
    post admin_designer_preview_path, params: { design: { hero_home: "no", bio_home: "no" } }, as: :json
    assert_response :no_content
    get admin_designer_preview_file_path(path: nil)
    assert_no_match(/fk-hero /, response.body)
    assert_no_match(/fk-author-band/, response.body)
    assert_match(/fk-books/, response.body)
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

  test "the section order reorders the home page and must be a permutation" do
    skip_unless_buildable
    sign_in_as users(:admin)

    post admin_designer_preview_path,
      params: { design: {}, sections: %w[bio hero books posts authors newsletter] }, as: :json
    assert_response :no_content
    get admin_designer_preview_file_path(path: nil)
    assert_operator response.body.index("fk-author-band"), :<, response.body.index("fk-hero "),
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
                colors: { bg: "#0ea5e9", accent: "#f59e0b", ink: "#dc2626" } }, as: :json
    assert_response :no_content

    saved = accounts(:merovex).reload.design
    assert_equal "pine", saved["design"]["palette"]
    assert_equal "Lobster", saved["fonts"]["display"]
    # Colors are stored RAW — the exporter resolves them per build.
    assert_equal "#0ea5e9", saved["colors"]["bg"]

    # Same gates as the preview: an unknown axis value is refused, and a bad
    # save leaves the previously-saved design untouched.
    patch admin_designer_path, params: { design: { palette: "vantablack" } }, as: :json
    assert_response :unprocessable_entity
    assert_match(/not in theme/, response.parsed_body["error"])
    assert_equal "pine", accounts(:merovex).reload.design["design"]["palette"]
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
    assert_match(/fk-brand-logo/, response.body)
    assert_match(/alt="?Merovex Press"?/, response.body)
    assert_no_match(/fk-brand-name/, response.body)

    # title_as_alt: false shows the title beside the logo, alt empties.
    post admin_designer_preview_path, params: { design: {}, nav: { title_as_alt: false } }, as: :json
    get admin_designer_preview_file_path(path: nil)
    assert_match(/fk-brand-name"?>Merovex Press</, response.body)
    assert_match(/fk-brand-lockup/, response.body)

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

  private
    # The preview pipeline needs the filibuster checkout (a sibling repo in
    # dev) and the pinned Hugo binary; CI wiring for both is the planned
    # theme sync gate (docs/site-designer.md §2.1).
    def skip_unless_buildable
      skip "filibuster theme not checked out beside the app" unless THEME_PATH.join("data/theme.json").exist?
      skip "hugo binary not available" unless system("#{HUGO_BIN} version", out: File::NULL, err: File::NULL)
    end
end
