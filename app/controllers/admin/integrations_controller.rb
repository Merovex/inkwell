# The Integrations tab of System settings: what an author pastes into a
# reader-magnet partner (BookFunnel's "Sendy" integration, and anything else
# that speaks Sendy) so new readers land on this site's list in real time.
#
# Opening the tab mints the account's key if it doesn't have one yet — a site
# that never connects a partner never stores a credential.
class Admin::IntegrationsController < Admin::BaseController
  def show
    @api_key = Current.account.sendy_api_key!
    @list_id = Current.account.handle.presence || Current.account.slug
    # The origin BookFunnel appends /subscribe to. The app host, always: a
    # tenant domain is served by the edge Worker, whose island allowlist
    # doesn't carry this path, so a push there would take a 405. Unenforced
    # (dev) there is only one host, and it's the one we're on.
    @host_url = AccountHost.enforced? ? "https://#{AccountHost.app_host}" : request.base_url
  end
end
