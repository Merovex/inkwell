# Install-wide system settings — the domain admin editing the Merovex Press
# identity. Always the singleton Setting.current, so no id in the URL (like the
# personal Admin::User::SettingsController, but install-scoped and admin-only).
class Admin::SettingsController < ApplicationController
  include AdminOnly

  before_action :set_setting

  def show
  end

  def update
    if @setting.update(setting_params)
      redirect_to admin_settings_path, notice: "Settings saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def set_setting
      @setting = Setting.current
    end

    def setting_params
      params.expect(setting: [ :site_name, :tagline, :description, :contact_email, :logo, :privacy_policy, :terms ])
    end
end
