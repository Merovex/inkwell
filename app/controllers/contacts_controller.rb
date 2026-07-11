# Public contact form — anonymous, double opt-in, mirroring SubscriptionsController.
# create records an unconfirmed Missive and emails a fixed-template confirmation
# link; confirm flips it to confirmed so it surfaces in /admin/missives. Spam is
# filtered two ways: a honeypot/timing trap (invisible_captcha) and a create rate
# limit. The submitter's name/subject/body are never emitted in outbound mail.
class ContactsController < PublicController
  invisible_captcha only: :create, on_spam: :discard_spam, on_timestamp_spam: :discard_spam

  rate_limit to: 5, within: 3.minutes, only: :create,
    with: -> { redirect_to contact_path, alert: "Too many attempts. Try again later." }

  def new
    @missive = Missive.new
  end

  def create
    @missive = Missive.new(missive_params)
    if @missive.valid?
      Missive.submit(**missive_params.to_h.symbolize_keys, ip: request.remote_ip)
      redirect_to contact_sent_path
    else
      flash.now[:alert] = "Please fix the errors below and try again."
      render :new, status: :unprocessable_entity
    end
  end

  # The "check your inbox" page — a single centered card, no site chrome.
  def sent
    render layout: "public_minimal"
  end

  def confirm
    missive = Missive.find_by_token_for(:confirmation, params[:token])
    if missive
      missive.confirm!
      render :confirmed
    else
      render :invalid_token, status: :not_found
    end
  end

  private
    def missive_params
      params.expect(missive: %i[name email_address subject body])
    end

    # A bot tripped the honeypot/timing trap: pretend it worked, persist nothing.
    # Same destination as a real submit, so the two are indistinguishable.
    def discard_spam
      redirect_to contact_sent_path
    end
end
