module AuthorsHelper
  # A public byline: the persona's name linked to their page, or the account
  # holder's display name for content with no author set.
  def byline_link(recordable)
    if (author = recordable.author)
      link_to author.name, author_page_path(author.public_slug), class: "press-link"
    else
      recordable.record.creator.display_name
    end
  end
end
