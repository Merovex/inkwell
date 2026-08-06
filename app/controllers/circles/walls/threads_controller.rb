# The Wall's thread modal: one story — a Message or a pulse answer (Beat) —
# plus its comments, fetched into the wall's "modal" frame (the goals-today
# pattern — the response carries a <dialog> that shows itself). Comment
# submits post back=wall and land here again, so the modal re-renders with
# the new comment instead of navigating away.
module Circles
  module Walls
    class ThreadsController < BaseController
      def show
        @record = @circle.records.listed
          .where(recordable_type: %w[ Message Beat ]).find(params[:id])
        @subject = @record.recordable
        # A beat wears its question as the title, like its wall card.
        @title = @subject.try(:title) || @record.parent.recordable.question
      end
    end
  end
end
