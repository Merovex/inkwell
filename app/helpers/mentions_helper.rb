# Renders rich text with recognized @mentions highlighted — only tokens that
# actually match a circle member light up (same matching as Mentions), so the
# highlight doubles as confirmation the mention landed. Non-circle content
# passes through untouched.
module MentionsHelper
  def mentions_highlighted(content, record)
    html = content.to_s
    tokens = mention_tokens_for(record.bucket)
    return html.html_safe if tokens.empty? || !html.include?("@")

    fragment = Nokogiri::HTML5.fragment(html)
    # Skip text already inside a rendered mention chip (attachment mentions
    # arrive pre-wrapped by users/_mention) — no double-wrapping.
    fragment.xpath(".//text()[not(ancestor::action-text-attachment) and not(ancestor::*[contains(concat(' ', @class, ' '), ' mention ')])]").each do |node|
      next unless node.text.include?("@")

      replaced = ERB::Util.html_escape(node.text).gsub(Mentions::TOKEN) do |match|
        tokens.include?($1.downcase) ? %(<span class="mention">#{match}</span>) : match
      end
      node.replace(replaced)
    end
    fragment.to_html.html_safe
  end

  # The @-picker for a circle composer (nests inside rich_textarea's block);
  # nothing outside a circle.
  def mention_prompt(bucket)
    render "circles/mention_prompt", circle: bucket if bucket.is_a?(Circle)
  end

  private
    # A circle's mentionable tokens (handles + emails), once per request.
    def mention_tokens_for(bucket)
      return Set.new unless bucket.is_a?(Circle)

      @mention_tokens ||= {}
      @mention_tokens[bucket.id] ||= bucket.members.pluck(:name, :email_address)
        .flatten.compact.map(&:downcase).to_set
    end
end
