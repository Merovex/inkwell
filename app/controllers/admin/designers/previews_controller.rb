# The SiteDesigner's preview: stateless build-from-payload
# (docs/site-designer.md §2.3). The working design lives in the browser
# (localStorage — scaffolding until the schema settles), so create receives
# the design JSON, builds it with the account's current published content
# through the real exporter + Hugo pipeline, and show serves the built
# files into the editor's iframe. Nothing here persists anything.
class Admin::Designers::PreviewsController < Admin::BaseController
  # show serves the built site's files — including its JavaScript — into
  # the preview iframe. Forgery protection would 422 controller-served JS
  # on plain GETs (the cross-origin <script> embedding defense); a GET
  # file-server carries no CSRF surface, and the auth gate stays.
  skip_forgery_protection only: :show

  def create
    workspace = Exporter.new(Current.account,
      design: design_params,
      nav: nav_params,
      fonts: fonts_params,
      colors: colors_params,
      hero: hero_params,
      newsletter: newsletter_params,
      sections: sections_params,
      base_url: "#{admin_designer_preview_file_path(path: nil)}/",
      preview: true).export!
    Renderer.new(workspace).render!(destination: preview_root, clean: true)
    head :no_content
  rescue Theme::InvalidDesign => error
    render json: { error: error.message }, status: :unprocessable_entity
  ensure
    FileUtils.rm_rf(workspace) if workspace  # workspaces are ephemeral (§5.2)
  end

  # Development only: the designer polls this and rebuilds the preview when
  # the theme tree changes, so theme edits show up like live reload.
  def version
    head :not_found and return unless Rails.env.development?

    render json: { version: Theme.current.fingerprint }
  end

  def show
    file = preview_root.join(params[:path].presence || "index.html").cleanpath
    file = file.join("index.html") if file.directory?

    if file.file? && file.to_s.start_with?("#{preview_root}/")
      send_file file, disposition: :inline,
        type: Mime::Type.lookup_by_extension(file.extname.delete("."))&.to_s || "application/octet-stream"
    else
      head :not_found
    end
  end

  private
    # Fixed per-account destination, rebuilt in place on every POST; the
    # iframe reloads only after the build returns, so it never reads a
    # half-written tree in practice. (Reader builds get pointer-flip
    # atomicity; the single-author preview doesn't need it.) Parallel test
    # workers each get their own tree — the fixture account is shared, and
    # one worker's clean rebuild would clobber another's mid-assertion.
    def preview_root
      Rails.root.join("tmp/builds", Current.account.slug,
        Rails.env.test? ? "preview-#{Process.pid}" : "preview")
    end

    # The design is a flat axis-key → option-id hash whose vocabulary
    # belongs to the theme, not the app — Theme#permit! (called by the
    # Exporter) slices unknown keys and rejects unknown values.
    def design_params
      params.fetch(:design, {}).permit!.to_h
    end

    # The header-content block (schema-lab shape, docs/site-designer.md
    # §2.5): editable links + an optional CTA button. Anything that isn't a
    # hash (absent, null, or a stray string from stale designer state) means
    # "no nav content" — the theme renders its defaults.
    def nav_params
      nav = params[:nav]
      return nil unless nav.is_a?(ActionController::Parameters)

      nav.permit(:title_as_alt, links: %i[id label url visible], button: %i[label url new_tab visible]).to_h
    end

    # The hero content block (schema-lab shape): source picks what the copy
    # says (author's name & bio / featured book & description / the
    # author's own words); headline and lede are the custom words; book
    # picks the featured cover by slug. All plain strings — Hugo's
    # templates escape them, and an unknown slug just falls back to the
    # newest release.
    # lede_html is the one rich field: sanitized here on EVERY build (the
    # contract ships pre-rendered, sanitized HTML — the body_html pattern),
    # with an allowlist narrowed to prose.
    HERO_HTML_TAGS = %w[ p br strong em b i a ul ol li blockquote ].freeze
    HERO_HTML_ATTRIBUTES = %w[ href ].freeze

    def hero_params
      hero = params[:hero]
      return nil unless hero.is_a?(ActionController::Parameters)

      hero.permit(:source, :headline, :lede, :lede_html, :book).to_h.compact_blank.tap do |block|
        if block["source"] && !block["source"].in?(%w[author featured custom])
          raise Theme::InvalidDesign, "#{block["source"].inspect} is not a hero copy source"
        end
        if block["lede_html"]
          # Prune first: the allowlist pass strips disallowed TAGS but keeps
          # their text — script bodies must go entirely.
          pruned = Loofah.html5_fragment(block["lede_html"]).scrub!(:prune).to_s
          block["lede_html"] = ActionText::ContentHelper.sanitizer.sanitize(
            pruned, tags: HERO_HTML_TAGS, attributes: HERO_HTML_ATTRIBUTES)
        end
      end.presence
    end

    # The home-page section order (the contract's home.sections). Must be a
    # PERMUTATION of the known sections — the order editor reorders, it
    # never adds or drops (visibility is each section's own axis).
    HOME_SECTIONS = %w[ hero books posts bio newsletter ].freeze

    def sections_params
      list = params[:sections]
      return nil unless list.is_a?(Array)

      list = list.map(&:to_s)
      unless list.sort == HOME_SECTIONS.sort
        raise Theme::InvalidDesign, "sections must be an ordering of #{HOME_SECTIONS.join(", ")}"
      end
      list
    end

    # The email-collection copy (schema-lab shape): headline / blurb /
    # button label, plain strings — Hugo's templates escape them; blank
    # keeps the fed defaults.
    def newsletter_params
      block = params[:newsletter]
      return nil unless block.is_a?(ActionController::Parameters)

      block.permit(:headline, :blurb, :button_label).to_h.compact_blank.presence
    end

    # Custom palette override (the escape valve past the palettes): authors
    # pick three colors — wheel presets or free hex — and PaletteColor keeps
    # only their chroma + hue, driving the lightness per role and mode (the
    # a11y policy). Output hexes are regenerated, never interpolated from
    # input.
    def colors_params
      colors = params[:colors]
      return nil unless colors.is_a?(ActionController::Parameters)

      colors.permit(:bg, :accent, :ink).to_h.to_h do |role, hex|
        raise Theme::InvalidDesign, "#{hex.inspect} is not a #rrggbb color" unless PaletteColor.valid?(hex)

        [ role, PaletteColor.resolve(role, hex) ]
      end
    end

    # Custom heading/body override (the escape valve past the pairings).
    # Family names are interpolated into the theme's <link>/<style>, so only
    # exact names from the vendored list pass — anything else fails loudly.
    def fonts_params
      fonts = params[:fonts]
      return nil unless fonts.is_a?(ActionController::Parameters)

      fonts.permit(:display, :body).to_h.compact_blank.tap do |picks|
        picks.each_value do |family|
          raise Theme::InvalidDesign, "#{family.inspect} is not a known Google Font" unless GoogleFonts.valid?(family)
        end
      end.presence
    end
end
