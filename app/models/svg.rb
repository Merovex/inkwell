# Tiny SVG facts reader — no XML parser, just what the tinted-logo pipeline
# needs (ApplicationHelper#svg_logo_style and the Exporter): the drawing's
# aspect ratio, so the CSS mask box can be sized (a mask can't size itself
# from the file the way an <img> can).
module Svg
  # Width/height ratio from the viewBox (else the root width/height
  # attributes); nil when the file declares no usable size.
  def self.aspect_ratio(svg)
    if (box = svg[/viewBox\s*=\s*["']([^"']+)["']/i, 1])
      _, _, w, h = box.split(/[\s,]+/).map(&:to_f)
    else
      w = dimension(svg, "width")
      h = dimension(svg, "height")
    end
    (w / h).round(4) if w&.positive? && h&.positive?
  end

  def self.dimension(svg, name)
    svg[/<svg\b[^>]*\b#{name}\s*=\s*["']([\d.]+)(?:px)?["']/i, 1]&.to_f
  end
  private_class_method :dimension
end
