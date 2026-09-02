# Public buy-link redirect: counts the click, then sends the reader off to the
# store. The destination is an admin-curated store URL (not user input), so the
# off-host redirect is safe. Post-cutover this is a Worker-proxied island (the
# theme's buy buttons point at /buy/:id), so it wears the same origin lockdown
# as the newsletter endpoints.
class DistributorsController < PublicController
  include IslandProtected

  def show
    # Tenant-scoped: a buy link only redirects on its own press's domain, so
    # one site's ids can't be enumerated (or click-counted) from another's.
    distributor = Current.account.distributors.find(params[:id])
    distributor.click
    redirect_to distributor.url, allow_other_host: true
  end
end
