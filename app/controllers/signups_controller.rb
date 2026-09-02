# Self-registration, gated by a join code (the invite is the policy — there is
# no open-registration switch). Spam is filtered two ways: the honeypot/timing
# trap fakes the success page without persisting anything, and a create rate
# limit blunts code guessing on top of the code check itself.
class SignupsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access

  invisible_captcha only: :create, on_spam: :pretend_sent, on_timestamp_spam: :pretend_sent

  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_signup_path, alert: "Too many attempts. Try again later." }

  def new
    @signup = Signup.new(invite_code: params[:code])
  end

  def create
    @signup = Signup.new(signup_params)
    if @signup.save
      redirect_to new_session_path(sent: true)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # A bot tripped the honeypot: pretend it worked, persist nothing. Same
  # destination as a real signup, so the two are indistinguishable.
  def pretend_sent
    redirect_to new_session_path(sent: true)
  end

  def signup_params
    params.expect(signup: [ :email_address, :invite_code ])
  end
end
