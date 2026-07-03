module PostsHelper
  # The history feed line for a version, derived from the delta against its
  # predecessor: the event tag narrates transitions; content and title changes
  # are detected by column comparison (body_id / title) — no rich text loads.
  def version_event_line(version, previous)
    return "created this post" if previous.nil?

    case version.event
    when "updated"
      if version.body_id == previous.body_id && version.title != previous.title
        %(changed the title of this post from “#{previous.title}” to “#{version.title}”)
      else
        "saved a new version of this post"
      end
    when "scheduled"   then "scheduled this post to publish #{version.published_at.strftime('%b %-d at %H:%M')}"
    when "unscheduled" then "unscheduled this post"
    when "published"   then "published this post"
    when "unpublished" then "reverted this post to a draft"
    when "pinned"      then "pinned this post"
    when "unpinned"    then "unpinned this post"
    when "trashed"     then "moved this post to the trash"
    when "restored"    then "restored this post from the trash"
    else version.event
    end
  end

  # The counted link to unpublished work, worded by what exists.
  def unpublished_posts_label(drafts_count, scheduled_count)
    if scheduled_count.positive? && drafts_count.positive?
      "Edit your #{pluralize(scheduled_count, 'scheduled post')} and #{pluralize(drafts_count, 'draft')}…"
    elsif scheduled_count.positive?
      "Edit your #{pluralize(scheduled_count, 'scheduled post')}"
    else
      "Edit your #{pluralize(drafts_count, 'draft')}…"
    end
  end

  def version_timestamp(version)
    version.created_at.strftime("%b %-d at %H:%M")
  end
end
