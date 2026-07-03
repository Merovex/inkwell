module ApplicationHelper
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
end
