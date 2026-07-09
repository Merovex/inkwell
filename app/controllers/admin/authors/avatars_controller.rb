# An author's avatar as a resource — the same auto-submitting well as the user's
# own picture. PATCH swaps it, DELETE reverts to the monogram.
class Admin::Authors::AvatarsController < ApplicationController
  include AdminOnly

  before_action :set_author

  def update
    if @author.update(avatar_params)
      redirect_to edit_admin_author_path(@author), notice: "Picture updated."
    else
      redirect_to edit_admin_author_path(@author), alert: @author.errors.full_messages.to_sentence
    end
  end

  def destroy
    @author.avatar.purge_later
    redirect_to edit_admin_author_path(@author), notice: "Picture removed — using initials."
  end

  private
    def set_author
      @author = Record.active.authors.find(params[:author_id]).recordable
    end

    def avatar_params
      params.expect(author: [ :avatar ])
    end
end
