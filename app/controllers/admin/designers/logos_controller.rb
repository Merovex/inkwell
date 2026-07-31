# The SiteDesigner's logo slot — the Site's own logo attachment (the same
# one System settings edits), so uploading here persists immediately: images
# can't ride the localStorage schema lab. The Site model enforces type and
# size (acceptable_logo).
class Admin::Designers::LogosController < Admin::BaseController
  def update
    site = Current.account.site

    if site.update(logo: params.expect(:logo))
      render json: { url: url_for(site.logo) }
    else
      render json: { error: site.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  # Synchronous purge: the designer rebuilds the preview immediately after,
  # and the exporter must see the attachment already gone.
  def destroy
    Current.account.site.logo.purge
    head :no_content
  end
end
