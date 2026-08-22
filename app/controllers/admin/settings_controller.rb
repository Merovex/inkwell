# System settings — the domain admin editing the account's public identity.
# Always the account's one Site (no id in the URL); contact_email rides the
# form via Site's delegation to the account and is saved alongside.
class Admin::SettingsController < Admin::BaseController
  before_action :set_site

  def show
  end

  def update
    # One form, two account rows (contact_email and handle delegate to the
    # account): save both or neither. The account save is non-bang — a bad
    # handle is a user-facing validation error, not an exception — with its
    # errors imported onto the site so the form fields show them.
    saved = Site.transaction do
      (@site.update(site_params) && @site.account.save) || raise(ActiveRecord::Rollback)
    end

    if saved
      # "Remove logo and use the wordmark" — purge only once the save sticks.
      @site.logo.purge if params.dig(:site, :remove_logo) == "1"
      redirect_to admin_settings_path, notice: "Settings saved."
    else
      @site.account.errors.each { |error| @site.errors.import(error) }
      render :show, status: :unprocessable_entity
    end
  end

  private
    def set_site
      @site = Current.account.site
    end

    def site_params
      params.expect(site: [ :site_name, :tagline, :contact_email, :handle, :logo ])
    end
end
