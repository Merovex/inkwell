# A curated collection of books — a bundle, a themed shelf, anything. A
# recordable on the spine, Publishable and Installable exactly like Series
# (drafts mutate in place, published content versions on every save, ordered
# books via the Installment join). Distinct from Series only in intent: a
# Series is a reading sequence; a Collection is any grouping the author curates.
class Collection < ApplicationRecord
  include Publishable
  include Authored
  include Installable
end
