# Removing a boost — only ever your own. The Current.user scope is the
# entire authorization: someone else's boost id 404s rather than 403s.
class BoostsController < ApplicationController
  def destroy
    boost = Current.user.boosts.find(params[:id])
    record = boost.record
    boost.destroy

    redirect_to post_path(record.parent_id || record.id, anchor: helpers.dom_id(record, :boosts))
  end
end
