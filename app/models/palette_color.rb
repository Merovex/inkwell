# Resolves an author-picked color (any #rrggbb) into designed light/dark
# values per role. A11y is structural — the continuous generalization of
# the old Tailwind stop policy: we keep the pick's OKLCH chroma and hue
# (the author's identity) but DRIVE the lightness and cap the chroma per
# role and mode, so any submitted hue lands at shades with dependable
# contrast. Output hexes are regenerated here, never interpolated from
# input, which is also what makes free hex entry injection-safe.
class PaletteColor
  HEX = /\A#\h{6}\z/

  # role => mode => [lightness, max chroma] — mirrors the feel of Tailwind's
  # 50/950 (bg), 700/400 (accent), 900/100 (ink) stops.
  POLICY = {
    "bg"     => { "light" => [ 0.985, 0.02 ], "dark" => [ 0.145, 0.04 ] },
    "accent" => { "light" => [ 0.50,  0.20 ], "dark" => [ 0.75,  0.17 ] },
    "ink"    => { "light" => [ 0.21,  0.06 ], "dark" => [ 0.96,  0.02 ] }
  }.freeze

  def self.valid?(hex) = hex.to_s.match?(HEX)

  # { "light" => hex, "dark" => hex } for a role from any picked color.
  def self.resolve(role, hex)
    _lightness, chroma, hue = oklch(hex)
    POLICY.fetch(role).transform_values do |(lightness, max_chroma)|
      to_hex(lightness, chroma.clamp(0, max_chroma), hue)
    end
  end

  # --- OKLCH <-> sRGB (standard Björn Ottosson matrices) ---

  def self.oklch(hex)
    r, g, b = hex.delete("#").scan(/../).map { |c| srgb_to_linear(c.to_i(16) / 255.0) }
    l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    b2 = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    [ lightness, Math.sqrt(a**2 + b2**2), Math.atan2(b2, a) ]
  end

  def self.to_hex(lightness, chroma, hue)
    a = chroma * Math.cos(hue)
    b2 = chroma * Math.sin(hue)
    l = (lightness + 0.3963377774 * a + 0.2158037573 * b2)**3
    m = (lightness - 0.1055613458 * a - 0.0638541728 * b2)**3
    s = (lightness - 0.0894841775 * a - 1.2914855480 * b2)**3
    rgb = [
      +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    ]
    format("#%02x%02x%02x", *rgb.map { |c| (linear_to_srgb(c.clamp(0.0, 1.0)) * 255).round })
  end

  def self.srgb_to_linear(c) = c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
  def self.linear_to_srgb(c) = c <= 0.0031308 ? c * 12.92 : 1.055 * c**(1 / 2.4) - 0.055
end
