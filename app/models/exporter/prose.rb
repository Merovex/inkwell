# Rich text as portable HTML — a body that can leave the Rails app. Shared by
# the Hugo transport (Exporter) and the author's archive (Export::Archive),
# so a rich-text fix lands in both.
#
# Rich text carries its images as ActionText attachments, rendered with
# ActiveStorage URLs that point back at the Rails app — nothing outside the
# app can serve those. So every image attachment is handed to the caller's
# block, which stores the blob wherever its output keeps images and returns
# the path the <img> should carry. `sizes` maps those paths to measured
# [width, height] when the caller has them (the Hugo build's CLS fix).
#
# The <action-text-attachment> wrapper is unwrapped on the way out: it's a
# custom element with no styling anywhere but the composer, and browsers lay
# it out inline, which boxes the figure wrongly. What ships is plain
# <figure><img></figure>.
#
# Untouched: mentions and other non-blob attachables (they carry their own
# inline HTML), and non-image blobs — a PDF in a body would need a place to
# live on the far side, which is a separate decision.
class Exporter::Prose
  def initialize(sizes: {}, &store)
    @sizes = sizes
    @store = store
  end

  # Rendered rich text as an HTML string, stripped of dev's template
  # annotation comments (Body::TEMPLATE_ANNOTATION) — output must be
  # byte-identical across environments. User content can't collide: the
  # sanitizer already strips comments from rich text.
  def html(rich_text)
    # Cleared rich text still renders its ActionText wrapper div, which is
    # emphatically not "no content": consumers decide whether to render a
    # prose block by asking whether the HTML is empty, so blank has to arrive
    # as blank.
    return "" if rich_text.blank?

    localize_attachments(rich_text.to_s.gsub(Body::TEMPLATE_ANNOTATION, ""))
  end

  private
    def localize_attachments(html)
      return html unless html.include?("action-text-attachment")

      fragment = Nokogiri::HTML5.fragment(html)
      fragment.css("action-text-attachment[sgid]").each do |node|
        blob = attachment_blob(node)
        next unless blob&.image?

        repoint(node, @store.call(blob))
        # ActionText captions the file with its name and byte size when the
        # author didn't write one. That's composer chrome, not prose.
        node.css("figcaption").remove if node["caption"].blank?
        node.replace(node.children)
      end
      fragment.to_html
    end

    def attachment_blob(node)
      attachable = ActionText::Attachable.from_attachable_sgid(node["sgid"])
      attachable if attachable.is_a?(ActiveStorage::Blob)
    rescue ActiveRecord::RecordNotFound, ActiveSupport::MessageVerifier::InvalidSignature => error
      Rails.logger.warn("[exporter] unresolvable attachment in body: #{error.message}")
      nil
    end

    # Repoint the attachment's <img> at the stored copy, and stamp the
    # measured dimensions when known — an inline image is raw HTML in the
    # body, so nothing else can reserve its layout space.
    def repoint(node, path)
      width, height = @sizes[path]
      node.css("img").each do |img|
        img["src"] = path
        img.remove_attribute("srcset")
        img["width"], img["height"] = width, height if width
      end
    end
end
