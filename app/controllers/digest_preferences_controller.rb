# One-click weekly-digest cadence changes from the email footer. Tokened and
# login-free (the signed token in the URL is the auth), GET+mutate mirroring the
# newsletter's unsubscribe. The cadence is enum-constrained by the route.
class DigestPreferencesController < ApplicationController
  allow_unauthenticated_access
  layout "auth"

  def update
    @user = User.find_by_token_for(:digest_preferences, params[:token])
    if @user
      @user.update!(digest_cadence: params[:cadence])
      render :updated
    else
      render :invalid_token, status: :not_found
    end
  end
end
