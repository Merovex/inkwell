# The direct-download delivery page — the ungated twin of the claim page,
# for readers already on the list (its URL is what the author pastes into
# newsletters and the welcome sequence). A Worker-proxied island on the
# tenant site: no token, no signup, nothing spent on GET; the slug lookup is
# account-scoped so one press's link never resolves on another's domain.
class DeliveriesController < PublicController
  include IslandProtected

  layout "public_minimal"

  def show
    @magnet = Current.account.magnets.find(params[:id])

    # The slug tail anchors the lookup, so a link minted before a title edit
    # still resolves — send it on to the canonical spelling.
    redirect_to delivery_path(@magnet), status: :moved_permanently unless params[:id] == @magnet.to_param
  end
end
