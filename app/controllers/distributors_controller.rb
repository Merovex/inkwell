# Public buy-link redirect: counts the click, then sends the reader off to the
# store. The destination is an admin-curated store URL (not user input), so the
# off-host redirect is safe.
class DistributorsController < PublicController
  def show
    distributor = Distributor.find(params[:id])
    distributor.click
    redirect_to distributor.url, allow_other_host: true
  end
end
