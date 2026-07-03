require "diff/lcs"

# Word-level diff of two HTML fragments, emitting <ins>/<del> wrappers for the
# tracked-changes view. Tags and whitespace are atomic tokens and never get
# wrapped, so the output nests validly; each changed word is wrapped
# individually. Inputs must already be sanitized (pass them through the
# sanitize view helper) — the output is marked html_safe.
class HtmlDiff
  TOKEN = /<[^>]+>|[^<\s]+|\s+/

  def self.between(before_html, after_html)
    new(before_html.to_s, after_html.to_s).to_html
  end

  def initialize(before_html, after_html)
    @before = before_html.scan(TOKEN)
    @after = after_html.scan(TOKEN)
  end

  def to_html
    Diff::LCS.sdiff(@before, @after).map { |change|
      case change.action
      when "=" then change.new_element
      when "+" then wrap(change.new_element, "ins")
      when "-" then wrap(change.old_element, "del")
      when "!" then wrap(change.old_element, "del") + wrap(change.new_element, "ins")
      end
    }.join.html_safe
  end

  private
    def wrap(token, tag)
      return token if token.start_with?("<") || token.blank?
      "<#{tag}>#{token}</#{tag}>"
    end
end
