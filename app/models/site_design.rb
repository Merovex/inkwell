# The website design the SiteDesigner produces: the full working payload —
# the theme's design axes plus the content blocks (nav, hero, newsletter,
# section order) and the custom fonts/colors escape valves. One object owns
# "is this a valid design?" so the preview build (Previews#create) and the
# Save-to-account path (Designers#update) validate the SAME way, in ONE
# place, rather than each re-checking the payload themselves.
#
# Values are held RAW, as the author picked them: colors stay #rrggbb picks
# (the Exporter resolves them to per-role light/dark shades at build time,
# the a11y policy in PaletteColor) so a saved design survives a policy
# change; design axes are sliced to the theme's vocabulary. The one
# transform done here is sanitizing the hero's rich lede — a safety boundary
# best crossed once, before the HTML is ever stored.
#
# Constructed from controller params; raises SiteDesign::Invalid (the app's
# one "this design is not acceptable" signal) so both controllers can rescue
# it into a 422 with a user-facing message.
class SiteDesign
  class Invalid < StandardError; end

  HERO_SOURCES = %w[ author featured custom ].freeze
  HOME_SECTIONS = %w[ hero books posts bio newsletter ].freeze
  HERO_HTML_TAGS = %w[ p br strong em b i a ul ol li blockquote ].freeze
  HERO_HTML_ATTRIBUTES = %w[ href ].freeze

  attr_reader :design, :nav, :fonts, :colors, :hero, :newsletter, :sections

  def initialize(params)
    @params = params
    @design = permit_design
    @nav = permit_nav
    @fonts = permit_fonts
    @colors = permit_colors
    @hero = permit_hero
    @newsletter = permit_newsletter
    @sections = permit_sections
  rescue Theme::InvalidDesign => error
    # The theme's vocabulary check speaks the same 422 as the rest.
    raise Invalid, error.message
  end

  # The raw, validated bundle: what the account stores and the exporter reads.
  def to_h
    { "design" => design, "nav" => nav, "fonts" => fonts, "colors" => colors,
      "hero" => hero, "newsletter" => newsletter, "sections" => sections }.compact_blank
  end

  private
    # A flat axis-key → option-id hash whose vocabulary belongs to the theme;
    # Theme#permit! slices unknown keys and rejects unknown values.
    def permit_design
      design = @params[:design]
      Theme.current.permit!(design.is_a?(ActionController::Parameters) ? design.permit!.to_h : {})
    end

    # The header-content block: editable links + an optional CTA button.
    # Anything that isn't a hash (absent, or a stray axis string from stale
    # designer state) means "no nav content" — the theme renders its default.
    def permit_nav
      nav = @params[:nav]
      return nil unless nav.is_a?(ActionController::Parameters)

      nav.permit(:title_as_alt, links: %i[id label url visible], button: %i[label url new_tab visible]).to_h.presence
    end

    # Custom heading/body override (the escape valve past the pairings).
    # Family names are interpolated into the theme's <link>/<style>, so only
    # exact names from the vendored list pass — anything else fails loudly.
    def permit_fonts
      fonts = @params[:fonts]
      return nil unless fonts.is_a?(ActionController::Parameters)

      fonts.permit(:display, :body).to_h.compact_blank.tap do |picks|
        picks.each_value do |family|
          raise Invalid, "#{family.inspect} is not a known Google Font" unless GoogleFonts.valid?(family)
        end
      end.presence
    end

    # Custom palette override (the escape valve past the palettes): three
    # #rrggbb picks, kept raw — PaletteColor.resolve turns them into
    # per-role/mode shades at build time.
    def permit_colors
      colors = @params[:colors]
      return nil unless colors.is_a?(ActionController::Parameters)

      colors.permit(:bg, :accent, :ink).to_h.compact_blank.tap do |picks|
        picks.each_value do |hex|
          raise Invalid, "#{hex.inspect} is not a #rrggbb color" unless PaletteColor.valid?(hex)
        end
      end.presence
    end

    # The hero content block: source picks what the copy says; headline/lede
    # are the custom words; book picks the featured cover by slug. lede_html
    # is the one rich field — sanitized here to a prose allowlist so only
    # pre-rendered, safe HTML is ever stored or built (the body_html pattern).
    def permit_hero
      hero = @params[:hero]
      return nil unless hero.is_a?(ActionController::Parameters)

      hero.permit(:source, :headline, :lede, :lede_html, :book).to_h.compact_blank.tap do |block|
        if block["source"] && !block["source"].in?(HERO_SOURCES)
          raise Invalid, "#{block["source"].inspect} is not a hero copy source"
        end
        block["lede_html"] = sanitize_lede(block["lede_html"]) if block["lede_html"]
      end.presence
    end

    # The email-collection copy: headline / blurb / button label, plain
    # strings — Hugo's templates escape them; blank keeps the fed defaults.
    def permit_newsletter
      block = @params[:newsletter]
      return nil unless block.is_a?(ActionController::Parameters)

      block.permit(:headline, :blurb, :button_label).to_h.compact_blank.presence
    end

    # The home-page section order (the contract's home.sections). Must be a
    # PERMUTATION of the known sections — the order editor reorders, it never
    # adds or drops (visibility is each section's own axis).
    def permit_sections
      list = @params[:sections]
      return nil unless list.is_a?(Array)

      list = list.map(&:to_s)
      unless list.sort == HOME_SECTIONS.sort
        raise Invalid, "sections must be an ordering of #{HOME_SECTIONS.join(", ")}"
      end
      list
    end

    # Prune first: the allowlist pass strips disallowed tags but keeps their
    # text — script bodies must go entirely.
    def sanitize_lede(html)
      pruned = Loofah.html5_fragment(html).scrub!(:prune).to_s
      ActionText::ContentHelper.sanitizer.sanitize(pruned, tags: HERO_HTML_TAGS, attributes: HERO_HTML_ATTRIBUTES)
    end
end
