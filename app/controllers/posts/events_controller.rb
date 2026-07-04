# The change history of a post: every version, oldest-to-newest, rendered as
# feed lines derived from adjacent-version deltas (see PostsHelper). Rich text
# is never loaded here — the whole page is a column read over the versions.
class Posts::EventsController < ApplicationController
  include PostScoped
  before_action -> { authorize! @record, to: :view }

  def index
    @versions = @record.versions.includes(:creator).to_a
    @current = @versions.last
  end
end
