# Public newsletter opt-in — anonymous, double opt-in. create records a pending
# subscriber, logs the consent event, and emails the tokened confirmation link
# (Subscriber.opt_in → SubscriberMailer#confirmation); confirm and unsubscribe
# are token-based. Spam is filtered two ways: a honeypot/timing trap
# (invisible_captcha) and a create rate limit, mirroring the auth controllers.
class SubscriptionsController < PublicController
  invisible_captcha only: :create, on_spam: :discard_spam, on_timestamp_spam: :discard_spam

  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to newsletter_path, alert: "Too many attempts. Try again later." }

  # The token-landing and interstitial pages render in the minimal layout, which
  # loads no ahoy.js — so a confirm/unsubscribe/keep hit (the signed token sits
  # in the URL) is never recorded as an Ahoy visit or page view. Everything else
  # keeps the tracked "public" layout inherited from PublicController.
  layout "public_minimal", only: %i[sent confirm unsubscribe keep]

  def new
  end

  def create
    Subscriber.opt_in(email_address: params[:email_address], source: params[:source], ip: request.remote_ip)
    redirect_to newsletter_sent_path
  rescue ActiveRecord::RecordInvalid
    log_rejected_signup
    # Deliberately vague: no oracle telling a prober which check tripped.
    redirect_to newsletter_path, alert: "That address can't receive mail — please try another."
  end

  # The "check your inbox" page — a single centered card, no site chrome.
  def sent
  end

  def confirm
    subscriber = Subscriber.find_by_token_for(:confirmation, params[:token])
    if subscriber.nil?
      render :invalid_token, status: :not_found
    else
      # Already confirmed (a re-click or an email-scanner prefetch got here
      # first) → show the "already done" message, not an error. confirm! is a
      # no-op when confirmed, so this is safe to call either way.
      @already_confirmed = subscriber.confirmed?
      subscriber.confirm!(ip: request.remote_ip)
      render :confirmed
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

    # The user-facing message stays vague, but the log says which hygiene
    # layer caught the address (format / reserved_tld / disposable) and
    # where the attempt came from — that's how we'll know what's actually
    # knocking on the door.
    def log_rejected_signup
      reason = Subscriber.rejection_reason(params[:email_address]) || "other"
      Rails.logger.warn(
        "[newsletter] rejected signup email=#{params[:email_address].inspect} " \
        "reason=#{reason} source=#{params[:source].inspect} ip=#{request.remote_ip}"
      )
    end
end
