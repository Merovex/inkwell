module ApplicationHelper
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

  # What goes inside an .avatar: the uploaded picture when there is one,
  # otherwise the monogram.
  def avatar_content(user)
    if user.avatar.attached?
      image_tag user.avatar.variant(:thumb), alt: user.display_name, class: "avatar__img"
    else
      avatar_initials(user)
    end
  end

  # Up-to-two-letter monogram for the avatar.
  def avatar_initials(user)
    user.display_name.scan(/[[:alpha:]]+/).first(2).map { |w| w[0] }.join.upcase
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
