# The vendored color scales behind the designer's wheel (Tailwind's 22 +
# the house ramps ported from the merovex token system). Purely picker
# data: the wheel's discs send their 500-stop hex as a fast preset into the
# same pipeline as free hex entry — PaletteColor owns the a11y policy.
class TailwindColors
  PATH = Rails.root.join("app/assets/data/tailwind_colors.json")

  def self.scales
    @scales ||= JSON.parse(PATH.read)
  end
end
