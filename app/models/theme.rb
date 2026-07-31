# A pre-baked Hugo theme's manifest (data/theme.json): the axis vocabulary,
# presets, and per-axis defaults (docs/hugo-build-pipeline.md §6.1). The
# manifest is the single source of truth for what a design block may say —
# the SiteDesigner renders its option rail from it, and the exporter
# validates against it at export time, because CSS attribute selectors fail
# silently: an unknown value must die here, before Hugo runs.
class Theme
  class InvalidDesign < StandardError; end

  def self.current
    new(THEME_PATH)
  end

  attr_reader :path

  def initialize(path)
    @path = Pathname(path)
  end

  def name = manifest.fetch("name")
  def version = manifest.fetch("version")
  def contract_version = manifest.fetch("contract_version")
  def axes = manifest.fetch("axes")
  def presets = manifest.fetch("presets")

  # The Google Fonts stylesheet declaring every pairing's families — the
  # same URL the theme's <head> uses; the designer loads it so font cards
  # render in their actual faces.
  def fonts_url = manifest["fonts_url"]

  # { "palette" => "nebula", ... } — the manifest's per-axis default.
  def defaults
    axes.to_h { |axis| [ axis["key"], axis["default"] ] }
  end

  # Newest mtime in the theme tree, as a comparable number. The SiteDesigner
  # polls this in development so editing the theme rebuilds the preview.
  def fingerprint
    Dir.glob(path.join("**/*")).map { |file| File.mtime(file) }.max.to_f
  end

  # An option's wireframe SVG (manifest `wireframe`, a static/-relative
  # path), inlined for the designer's option cards. First-party theme
  # content — trusted by the same standing as its templates.
  def wireframe(relative_path)
    file = path.join("static", relative_path)
    file.read.html_safe if file.file?
  end

  # Slims an untrusted hash down to known axis keys (string values only),
  # then validates every value against the axis vocabulary. Returns the
  # clean design hash; raises InvalidDesign so a bad value fails loudly.
  def permit!(design)
    design = (design || {}).to_h.transform_keys(&:to_s).slice(*defaults.keys)
    design.each do |key, value|
      axis = axes.find { |a| a["key"] == key }
      unless axis["options"].any? { |option| option["id"] == value }
        raise InvalidDesign, "design.#{key}: #{value.inspect} is not in theme #{name.inspect} vocabulary"
      end
    end
    design
  end

  private
    def manifest
      @manifest ||= JSON.parse(path.join("data/theme.json").read)
    end
end
