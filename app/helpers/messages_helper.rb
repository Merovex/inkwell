module MessagesHelper
  # The board byline leads with the category, Basecamp style: "📢 Announcement
  # by Ben Wilson". Without a category it's just the author.
  def message_author_line(message)
    author = message.record.creator.display_name
    message.category ? "#{message.category.label} by #{author}" : author
  end
end
