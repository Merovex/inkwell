# An author's hero portrait as a resource — the same auto-submitting well as
# the avatar. PATCH swaps it, DELETE reverts the hero to the bio avatar.
class Admin::Authors::HeroImagesController < Admin::BaseController
  before_action :set_author

  def update
    if @author.update(hero_image_params)
      redirect_to edit_admin_author_path(@author), notice: "Hero image updated."
    else
      redirect_to edit_admin_author_path(@author), alert: @author.errors.full_messages.to_sentence
    end
  end

  def destroy
    @author.hero_image.purge_later
    redirect_to edit_admin_author_path(@author), notice: "Hero image removed — using the bio photo."
  end

  private
    def set_author
      @author = Current.account.records.active.authors.find(params[:author_id]).recordable
    end

    def hero_image_params
      params.expect(author: [ :hero_image ])
    end
end
