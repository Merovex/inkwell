# A shareable rich-text owner. Versions reference a body by id, and a new body
# is minted only when the text actually changes — action-only versions
# (publish, pin, trash) point at the previous one. "Did the body change?" is
# therefore a body_id comparison, which keeps the history feed a column select.
class Body < ApplicationRecord
  has_rich_text :content
end
