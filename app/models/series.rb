# A book series — a recordable on the spine, Publishable exactly like Post
# (drafts mutate in place, published content versions on every save,
# scheduling via an event version + job). Its books are the Installment join,
# keyed by Record id so memberships survive versioning (see Installable).
class Series < ApplicationRecord
  include Publishable
  include Authored
  include Installable
end
