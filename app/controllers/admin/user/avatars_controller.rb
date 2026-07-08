# The avatar picture as a resource: PATCH swaps it (auto-submitted when a
# file is picked or dropped), DELETE reverts to the monogram.
class Admin::User::AvatarsController < ApplicationController
  def update
    if Current.user.update(avatar_params)
      redirect_to admin_user_settings_path, notice: "Picture updated."
    else
      redirect_to admin_user_settings_path, alert: Current.user.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.user.avatar.purge_later
    redirect_to admin_user_settings_path, notice: "Picture removed — using your initials."
  end

  private
    def avatar_params
      params.expect(user: [ :avatar ])
    end
end
