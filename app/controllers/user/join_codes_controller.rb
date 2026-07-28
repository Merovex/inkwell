# Rotating your invite code (shown in personal settings). Only inviters have
# one (User#can_invite?); everyone else gets the standard 404.
class User::JoinCodesController < ApplicationController
  def update
    return render_not_found unless Current.user.can_invite?

    (Current.user.join_code || Current.user.create_join_code!).rotate!
    redirect_to user_settings_path, notice: "Invite code rotated — the old code no longer works."
  end
end
