# System settings — the domain admin editing the account's public identity.
# Always the account's one Site (no id in the URL); contact_email rides the
# form via Site's delegation to the account and is saved alongside.
class Admin::SettingsController < Admin::BaseController
  before_action :set_site

  def show
  end

  def update
    # One form, two rows (contact_email delegates to the account): save both
    # or neither.
    saved = Site.transaction { @site.update(site_params) && @site.account.save! }

    if saved
      # "Remove logo and use the wordmark" — purge only once the save sticks.
      @site.logo.purge if params.dig(:site, :remove_logo) == "1"
      redirect_to admin_settings_path, notice: "Settings saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def set_site
      @site = Current.account.site
    end

    def site_params
      params.expect(site: [ :site_name, :tagline, :description, :contact_email, :logo, :privacy_policy, :terms ])
    end
end
