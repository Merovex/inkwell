# Adds a boost to any active record (:record_id is the Record id, as
# everywhere). The creator defaults to Current.user via the model. A blank
# submission fails validation and simply adds nothing — no error ceremony
# for a sixteen-character input.
class Records::BoostsController < ApplicationController
  def create
    @record = Record.active.find(params[:record_id])
    @record.boosts.create(boost_params)

    redirect_to page_path(@record)
  end

  private
    def boost_params
      params.expect(boost: [ :content ])
    end

    # The page carrying the record's boost strip: the post page, whether the
    # record is the post itself or a comment under it. Turbo extracts the
    # strip's frame from the response, so the swap happens in place.
    def page_path(record)
      post_path(record.parent_id || record.id, anchor: helpers.dom_id(record, :boosts))
    end
end
