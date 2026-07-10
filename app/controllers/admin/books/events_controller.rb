# The change history of a book: every version, oldest-to-newest, rendered as
# feed lines derived from adjacent-version deltas (see PublishableHelper). Rich
# text is never loaded here — the whole page is a column read over the versions.
class Admin::Books::EventsController < Admin::BaseController
  include BookScoped
  before_action -> { authorize! @record, to: :view }

  def index
    @versions = @record.versions.includes(:creator).to_a
    @current = @versions.last
  end
end
