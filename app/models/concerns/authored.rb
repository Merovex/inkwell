# Give a recordable a public byline: an optional Author persona referenced by
# the author's Record id (stable, survives author edits — the Installment/
# Distributor pattern). Falls back to the account holder for content with no
# author set.
module Authored
  extend ActiveSupport::Concern

  # The current Author version for the chosen persona, or nil.
  def author
    Author.current.find_by(record_id: author_record_id) if author_record_id
  end

  # What the public site prints as the byline.
  def byline
    author&.name || record.creator.display_name
  end
end
