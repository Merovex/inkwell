# The SiteDesigner's hero-banner slot — like the logo, it persists to the
# Site immediately (images can't ride the localStorage schema lab); the
# Site model enforces type and size.
class Admin::Designers::BannersController < Admin::BaseController
  def update
    site = Current.account.site

    if site.update(banner: params.expect(:banner))
      render json: { url: url_for(site.banner) }
    else
      render json: { error: site.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  # Synchronous purge: the designer rebuilds the preview immediately after,
  # and the exporter must see the attachment already gone.
  def destroy
    Current.account.site.banner.purge
    head :no_content
  end
end
