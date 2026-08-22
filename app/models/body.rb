# A shareable rich-text owner. Versions reference a body by id, and a new body
# is minted only when the text actually changes — action-only versions
# (publish, pin, trash) point at the previous one. "Did the body change?" is
# therefore a body_id comparison, which keeps the history feed a column select.
class Body < ApplicationRecord
  # Development renders views with filename annotations
  # (annotate_rendered_view_with_filenames), which have no business inside
  # stored or exported content: they'd make a body differ between
  # environments. Anything that writes rendered HTML into a body (Page's
  # starter copy) or reads one back out for the transport (Exporter#html)
  # strips them with this.
  TEMPLATE_ANNOTATION = /<!-- (?:BEGIN|END) [^>]*-->\n?/m

  has_rich_text :content
end
