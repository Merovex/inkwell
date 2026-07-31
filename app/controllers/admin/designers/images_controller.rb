# The SiteDesigner's image slots — Site attachments (logo / hero banner /
# newsletter photo) behind one controller: images can't ride the
# localStorage schema lab, so uploads persist to the Site immediately and
# the model enforces type and size. The logo doubles as System settings'.
class Admin::Designers::ImagesController < Admin::BaseController
  SLOTS = %w[ logo banner newsletter_photo ].freeze

  before_action :set_slot

  def update
    site = Current.account.site

    if site.update(@slot => params.expect(@slot.to_sym))
      render json: { url: url_for(site.public_send(@slot)) }
    else
      render json: { error: site.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  # Synchronous purge: the designer rebuilds the preview immediately after,
  # and the exporter must see the attachment already gone.
  def destroy
    Current.account.site.public_send(@slot).purge
    head :no_content
  end

  private
    def set_slot
      @slot = params[:slot]
      head :not_found unless @slot.in?(SLOTS)
    end
end
