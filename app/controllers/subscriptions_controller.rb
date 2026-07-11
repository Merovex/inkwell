# Public newsletter opt-in — anonymous, double opt-in. create records a pending
# subscriber, logs the consent event, and emails the tokened confirmation link
# (Subscriber.opt_in → SubscriberMailer#confirmation); confirm and unsubscribe
# are token-based. Spam is filtered two ways: a honeypot/timing trap
# (invisible_captcha) and a create rate limit, mirroring the auth controllers.
class SubscriptionsController < PublicController
  invisible_captcha only: :create, on_spam: :discard_spam, on_timestamp_spam: :discard_spam

  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to newsletter_path, alert: "Too many attempts. Try again later." }

  def new
  end

  def create
    Subscriber.opt_in(email_address: params[:email_address], source: params[:source], ip: request.remote_ip)
    redirect_to newsletter_sent_path
  end

  # The "check your inbox" page — a single centered card, no site chrome.
  def sent
    render layout: "public_minimal"
  end

  def confirm
    subscriber = Subscriber.find_by_token_for(:confirmation, params[:token])
    if subscriber
      subscriber.confirm!(ip: request.remote_ip)
      render :confirmed
    else
      render :invalid_token, status: :not_found
    end
  end

  def unsubscribe
    subscriber = Subscriber.find_by_token_for(:unsubscribe, params[:token])
    if subscriber
      subscriber.unsubscribe!(ip: request.remote_ip)
      attribute_to_broadcast(subscriber)
      render :unsubscribed
    else
      render :invalid_token, status: :not_found
    end
  end

  # "Keep me subscribed" from a re-engagement nudge: reset the engagement clock
  # so the sunset sweep leaves them alone.
  def keep
    subscriber = Subscriber.find_by_token_for(:unsubscribe, params[:token])
    if subscriber&.confirmed?
      subscriber.mark_engaged!
      render :kept
    else
      render :invalid_token, status: :not_found
    end
  end

  private
    # When the link came from a broadcast email (carries b=<broadcast_id>),
    # record the opt-out against that issue's delivery so it shows on the
    # broadcasts dashboard. Metrics only; a missing/mismatched delivery is a no-op.
    def attribute_to_broadcast(subscriber)
      return if params[:broadcast].blank?

      BroadcastDelivery.find_by(broadcast_id: params[:broadcast], subscriber_id: subscriber.id)
        &.record_event!("unsubscribed")
    end

    # A bot tripped the honeypot: pretend it worked, persist nothing. Same
    # destination as a real opt-in, so the two are indistinguishable.
    def discard_spam
      redirect_to newsletter_sent_path
    end
end
