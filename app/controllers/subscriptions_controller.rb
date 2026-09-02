# Public newsletter opt-in — anonymous, double opt-in. create records a pending
# subscriber, logs the consent event, and emails the tokened confirmation link
# (Subscriber.opt_in → SubscriberMailer#confirmation); confirm and unsubscribe
# are token-based. Post-cutover these actions are Worker-proxied islands on a
# static site (docs/newsletter-bot-protection-plan.md); the guards run
# cheapest-first — island auth → honeypot → rate limit → Turnstile — so a
# hammering bot burns 403s and 429s, not siteverify round-trips.
class SubscriptionsController < PublicController
  include IslandProtected

  # The signup form is baked into the static site: no Rails-rendered token,
  # no session cookie, so forgery protection can't apply to create. The
  # island/honeypot/rate-limit/Turnstile stack guards it instead.
  skip_forgery_protection only: :create

  # Pinned honeypot, hand-rolled — NOT invisible_captcha, whose session traps
  # reject every session-less submit (a missing session timestamp counts as
  # spam, and the spinner can only be disabled app-wide, which would weaken
  # the auth and contact controllers). The static form and this check share
  # one fixed field name via Subscriber::HONEYPOT_FIELD.
  before_action :discard_honeypot, only: :create

  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to newsletter_rejected_path }

  # The token-landing and interstitial pages render in the minimal layout, which
  # loads no ahoy.js — so a confirm/unsubscribe/keep hit (the signed token sits
  # in the URL) is never recorded as an Ahoy visit or page view. Everything else
  # keeps the tracked "public" layout inherited from PublicController.
  layout "public_minimal", only: %i[sent rejected confirm unsubscribe keep]

  def new
  end

  def create
    unless TurnstileVerifier.new(params["cf-turnstile-response"], account: Current.account).verified?
      log_rejected_signup(reason: "turnstile")
      return redirect_to newsletter_rejected_path
    end

    Subscriber.opt_in(email_address: params[:email_address], source: params[:source], ip: request.remote_ip)
    redirect_to newsletter_sent_path
  rescue ActiveRecord::RecordInvalid
    log_rejected_signup
    redirect_to newsletter_rejected_path
  end

  # The "check your inbox" page — a single centered card, no site chrome.
  def sent
  end

  # Where every blocked signup lands (hygiene reject, rate limit, failed
  # Turnstile) — deliberately vague, no oracle telling a prober which check
  # tripped. Its own island because the static site can't render a flash and
  # GET /newsletter isn't proxied.
  def rejected
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
    def discard_honeypot
      redirect_to newsletter_sent_path if params[Subscriber::HONEYPOT_FIELD].present?
    end

    # The user-facing message stays vague, but the log says which layer
    # caught the attempt (format / reserved_tld / disposable / turnstile) and
    # where it came from — that's how we'll know what's actually knocking on
    # the door.
    def log_rejected_signup(reason: nil)
      reason ||= Subscriber.rejection_reason(params[:email_address]) || "other"
      Rails.logger.warn(
        "[newsletter] rejected signup email=#{params[:email_address].inspect} " \
        "reason=#{reason} source=#{params[:source].inspect} ip=#{request.remote_ip}"
      )
    end
end
