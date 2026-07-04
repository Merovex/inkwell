# A version of a blog post — the first recordable on the spine. Rows are
# immutable once published; access always goes through the Record, whose id
# is the public identity (/posts/:id). The whole draft/schedule/publish
# regime lives in Publishable, shared with Message.
class Post < ApplicationRecord
  include Publishable
end
