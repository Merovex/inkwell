module ApplicationHelper
  # The product name — the one place it lives. Brands the admin <title> and any
  # app-level chrome; never hardcode it in a view again. (Public/tenant pages
  # brand with the author's own site_settings.site_name, not this.)
  APP_NAME = "Kindred Quill"

  # The admin document <title>: the page-specific part a view sets with
  # `content_for :title, "Posts"`, suffixed once with the app name here →
  # "Posts — Kindred Quill". No page title set → just the app name.
  def document_title
    [ content_for(:title).presence, APP_NAME ].compact.join(" — ")
  end

  # Version token mixed into the public book-cover fragment cache keys
  # (books/index, books/show). Book/Series records don't change when the cover
  # *variant definition* does (see Depiction#image), so those fragments — which
  # bake in signed Active Storage proxy URLs — won't self-invalidate on a deploy.
  # Bump this whenever the cover variant (size/format/preprocessing) changes so
  # stale fragments pointing at dead variant URLs are dropped. Last bump: v2 for
  # the [480,720] WebP preprocessed cover (was [600,900] JPG).
  def cover_fragment_version
    "covers-v2"
  end

  # Transformation for an Action Text image attachment. On the web we transcode
  # everything but already-modern formats to WebP; in email (the default) we keep
  # broad client support — WebP/AVIF are re-encoded to JPEG (Outlook can't render
  # them) and other raster formats pass through unchanged.
  def attachment_variation(blob, in_gallery:)
    variation = { resize_to_limit: in_gallery ? [ 800, 600 ] : [ 1024, 768 ] }
    modern = %w[image/webp image/avif]
    if Current.web_images
      variation[:format] = :webp unless blob.content_type.in?(modern)
    elsif blob.content_type.in?(modern)
      variation[:format] = :jpeg
    end
    variation
  end

  # Icons are rendered with inline_svg_tag from real SVG files under
  # app/assets/images (e.g. app/assets/images/lucide/*.svg). Never hand-write
  # icon path data here.

  # Rich text as plain text. A list row reads a post's body twice — excerpt and
  # length — so callers that need both parse once and pass the string back in.
  def plain_text(content)
    content.respond_to?(:to_plain_text) ? content.to_plain_text.to_s : content.to_s
  end

  # List-row excerpt from rich text (or plain_text output), truncated at a
  # word boundary so rows never end mid-wor…
  def plain_excerpt(content, length: 140)
    plain_text(content).truncate(length, separator: " ")
  end

  # The length fact in a post's status line and list row: "1,840 words, about 8
  # minutes" at ~225 wpm. The word-count Stimulus controller phrases the live
  # count in the composer identically, so the same post reads the same
  # everywhere. An empty body gets a bare "0 words" — estimating a read of
  # nothing yet written is noise.
  WORDS_PER_MINUTE = 225
  def post_length(content)
    words = plain_text(content).split.size
    count = "#{number_with_delimiter(words)} #{"word".pluralize(words)}"
    return count if words.zero?

    minutes = [ (words / WORDS_PER_MINUTE.to_f).round, 1 ].max
    "#{count}, about #{pluralize(minutes, "minute")}"
  end

  # Status chips for a post row: its state (green Published / yellow Scheduled /
  # neutral Draft), plus an "Emailed" chip once a published post has gone out.
  # [[label, badge_variant], …] for shared/list_item's trailing_chips.
  def post_status_chips(post)
    if post.published?
      chips = [ [ "Published", "success" ] ]
      if post.record.broadcast&.sent?
        chips << [ safe_join([ inline_svg_tag("lucide/mail.svg", class: "lucide", size: "14px"), " Emailed" ]), nil ]
      end
      chips
    elsif post.scheduled?
      # The schedule *is* the status — a yellow "Posts on …" chip, no separate
      # "Scheduled" word or flag row (local-time reformats it to the reader's zone).
      at = post.published_at
      label = safe_join([
        inline_svg_tag("lucide/clock.svg", class: "lucide", size: "14px"),
        " Posts on ",
        tag.time(at.strftime("%b %-d at %-l:%M %p"), datetime: at.iso8601,
          data: { controller: "local-time", local_time_datetime_value: at.iso8601 })
      ])
      [ [ label, "warning" ] ]
    else
      [ [ "Draft", nil ] ]
    end
  end

  # Relative time with the receipt on hover: "3 hours ago" whose title (the
  # native tooltip) carries the absolute timestamp. Every time-ago should
  # render through this. suffix: "" for contexts that phrase it themselves
  # (the bell's bare "5 minutes", a drip's time-until).
  def time_ago_tag(time, suffix: " ago")
    tag.time "#{time_ago_in_words(time)}#{suffix}",
      datetime: time.iso8601, title: l(time, format: :long)
  end

  # What goes inside an .avatar: the uploaded picture when there is one,
  # otherwise the monogram.
  def avatar_content(user)
    if user.avatar.attached?
      # The proxy PATH, not the URL: background renders (Turbo broadcasts —
      # boost chips, bell rows) have no request host, so the url form points
      # at the renderer's placeholder host (example.org) and breaks the image.
      image_tag rails_storage_proxy_path(user.avatar.variant(:thumb)),
        alt: user.display_name, class: "avatar__img"
    else
      avatar_initials(user)
    end
  end

  # Up-to-two-letter monogram for the avatar.
  def avatar_initials(user)
    user.display_name.scan(/[[:alpha:]]+/).first(2).map { |w| w[0] }.join.upcase
  end

  # Masked email for admin lists: the first three letters of the local part,
  # then a fixed three-dot mask (so the address length doesn't leak) and the
  # domain — "benjamin@hey.com" → "ben•••@hey.com".
  def redacted_email(address)
    local, domain = address.to_s.split("@", 2)
    masked = "#{local.to_s.first(3)}•••"
    domain ? "#{masked}@#{domain}" : masked
  end

  # The standard "who · when" line under list rows (comments, chat lines).
  def byline(creator, time, edited: false)
    tag.p class: "byline u-text-muted" do
      safe_join [
        tag.span(creator.display_name, class: "u-text-strong"),
        " · ",
        tag.time(time.strftime("%b %-d at %H:%M"), datetime: time.iso8601),
        (" · Edited" if edited)
      ].compact
    end
  end
end
