# The Wall's edit surface for a message: the composer fetched into the
# wall's "modal" frame (the thread-modal pattern). The form submits the
# ordinary messages#update with back=wall, landing the save back on the wall.
# Author-only, same predicate the ⋯ menu uses.
module Circles
  module Walls
    class EditsController < BaseController
      def show
        @record = @circle.records.listed.messages.find(params[:id])
        @message = @record.recordable
        raise ActiveRecord::RecordNotFound unless @record.editable_by?(Current.user)
      end
    end
  end
end
