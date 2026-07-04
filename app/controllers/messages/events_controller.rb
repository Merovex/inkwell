# The change history of a message: every version, oldest-to-newest, rendered
# as feed lines derived from adjacent-version deltas (see ApplicationHelper).
# Rich text is never loaded here — the whole page is a column read over the
# versions.
class Messages::EventsController < ApplicationController
  include MessageScoped

  def index
    @versions = @record.versions.includes(:creator).to_a
    @current = @versions.last
  end
end
