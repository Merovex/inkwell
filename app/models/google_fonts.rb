# The vendored Google Fonts family list (app/assets/data/google_fonts.json,
# popularity-ordered) — one file, two consumers: the designer's font-picker
# typeahead fetches it as an asset, and this validates custom picks
# server-side before a family name is interpolated into the theme's
# <link>/<style> (injection guard: only exact known names pass).
class GoogleFonts
  PATH = Rails.root.join("app/assets/data/google_fonts.json")

  def self.names
    @names ||= JSON.parse(PATH.read).map { it["name"] }.to_set
  end

  def self.valid?(name) = names.include?(name)
end
