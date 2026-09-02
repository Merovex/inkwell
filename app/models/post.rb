# A version of a blog post — the first recordable on the spine. Rows are
# immutable once published; access always goes through the Record, whose id
# is the public identity (/posts/:id). The whole draft/schedule/publish
# regime lives in Publishable, shared with Message.
class Post < ApplicationRecord
  include Publishable
  include Authored

  # The marker an author types in the body (own line, or via the composer
  # button): where the tip-in splices in when the post goes out as the
  # newsletter. Everything public renders via #public_content, so a marker
  # never reaches the site, the feed, or an excerpt.
  TIPIN_MARKER = /\{%\s*tipin\s*%\}/

  # The tip-in (bookbinding: a page glued into the bound book after printing)
  # — rich text only newsletter readers ever see, written in the composer
  # alongside the body and carried across versions in build_successor.
  has_rich_text :tipin

  # Keep the excerpt within the search-snippet sweet spot — Google clips a meta
  # description around 160 chars. (The 50-char floor is a composer nudge, not a
  # hard rule: a shorter one still beats none.)
  validates :excerpt, length: { maximum: 160 }, allow_blank: true

  # The blurb for the public blog list and the meta description: the author's
  # excerpt when given (an SEO-friendly summary), otherwise a truncation of the
  # body — the previous default.
  def summary(length: 300)
    excerpt.presence || public_content.to_plain_text.to_s.truncate(length)
  end

  # The body as the newsletter sends it: the tip-in spliced in at the first
  # {% tipin %} marker — after the article when there is none — and stray
  # markers gone either way.
  def email_content = body_with_tipin(spliced: true)

  # The body as every public surface shows it (blog, feed, Hugo export,
  # summaries): markers stripped, the tip-in never present.
  def public_content = body_with_tipin(spliced: false)

  # Carry the tip-in onto successors built without a :tipin change (action
  # versions, and edits that leave it alone) — the Author#bio trick, since
  # Recordable#build_successor's dup only carries scalars.
  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.tipin = tipin.body unless changes.key?(:tipin)
    end
  end

  private
    # One pass over the body's canonical HTML: blank every marker, then either
    # splice the tip-in into the first marker's paragraph (replacing it when
    # the marker stood alone, following it when text surrounds it) or sweep
    # the emptied paragraph away. Canonical-to-canonical, so attachments in
    # both parts render through the normal Action Text pipeline and
    # to_plain_text works untouched.
    def body_with_tipin(spliced:)
      fragment = Nokogiri::HTML5.fragment(content&.body&.to_html.to_s)
      tipin_html = (tipin.body.to_html if spliced && tipin.present?)

      markers = fragment.xpath(".//text()").select { |node| node.content.match?(TIPIN_MARKER) }
      slot = markers.first&.parent
      markers.each { |node| node.content = node.content.gsub(TIPIN_MARKER, "") }

      slot = nil if slot == fragment # a bare text marker has no paragraph to swap
      emptied = slot && slot.text.blank? && slot.element_children.none?

      if slot && tipin_html
        emptied ? slot.replace(tipin_html) : slot.add_next_sibling(tipin_html)
      elsif emptied
        slot.remove
      elsif tipin_html
        fragment.add_child(tipin_html)
      end

      ActionText::Content.new(fragment.to_html)
    end
end
