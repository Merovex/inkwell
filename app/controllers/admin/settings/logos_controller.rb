# The site logo as a resource — the same auto-submitting well as the user and
# author avatars. PATCH swaps it the moment a file is picked or dropped;
# DELETE reverts to the built-in wordmark. Deliberately independent of the
# settings form's Save, so an upload can never collide with a removal.
class Admin::Settings::LogosController < Admin::BaseController
  def update
    site = Current.account.site
    if site.update(logo_params)
      redirect_to admin_settings_path, notice: "Logo updated."
    else
      redirect_to admin_settings_path, alert: site.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.account.site.logo.purge_later
    redirect_to admin_settings_path, notice: "Logo removed — using the wordmark."
  end

  private
    def logo_params
      params.expect(site: [ :logo ])
    end
end
