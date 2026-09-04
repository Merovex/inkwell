# Rotating the subscribe endpoint's key. An update, not a verb: the account has
# one key, and this replaces its value. The old key stops working the moment
# this lands, so the partner has to be re-configured with the new one — which is
# the whole point of being able to do it.
class Admin::Integrations::SendyKeysController < Admin::BaseController
  def update
    Current.account.rotate_sendy_api_key!
    redirect_to admin_integration_path,
      notice: "New API key. Paste it into BookFunnel now — the old one stopped working."
  end
end
