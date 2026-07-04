# Adds a boost to any active record (:record_id is the Record id, as
# everywhere). The creator defaults to Current.user via the model. A blank
# submission fails validation and simply adds nothing — no error ceremony
# for a sixteen-character input.
class Records::BoostsController < ApplicationController
  def create
    @record = Record.active.find(params[:record_id])
    # Boosting follows visibility: no cheering for a draft you can't see.
    authorize! @record, to: :view
    @record.boosts.create(boost_params)

    redirect_to record_page_path(@record)
  end

  private
    def boost_params
      params.expect(boost: [ :content ])
    end
end
