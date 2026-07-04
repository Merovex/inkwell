# A message on the board (/forum) — the fourth recordable on the spine.
# Publishable exactly like Post (drafts mutate in place, published content
# versions on every save, scheduling via an event version + job) with one
# addition: an optional Category, worn in the byline. Category is a column
# like any other, so it carries across versions and its changes are history.
class Message < ApplicationRecord
  include Publishable

  belongs_to :category, optional: true
end
