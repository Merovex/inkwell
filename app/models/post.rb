# A version of a blog post — the first recordable on the spine. Rows are
# immutable once published; access always goes through the Record, whose id
# is the public identity (/posts/:id). The whole draft/schedule/publish
# regime lives in Publishable, shared with Message.
class Post < ApplicationRecord
  include Publishable

  # The blurb for the public blog list and the meta description: the author's
  # excerpt when given (an SEO-friendly summary), otherwise a truncation of the
  # body — the previous default.
  def summary(length: 300)
    excerpt.presence || content.to_plain_text.to_s.truncate(length)
  end
end
