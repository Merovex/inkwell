# "Send me a new link" from an expired claim page: renew every grant the
# address holds and mail fresh claim links. Renewing is half the job — the page
# is also what a reader who has spent the download cap sees, and a fresh token
# on a spent grant would land them right back here. Every outcome — links sent,
# unknown address, no grants — lands on the same "check your inbox" page, so
# the form is no oracle for probing which addresses subscribe. Guards mirror
# the newsletter signup, cheapest first: island auth → honeypot → rate limit.
class ClaimRenewalsController < PublicController
  include IslandProtected

  # Renders on tenant domains via the island proxy with no session; the only
  # thing the form can do is mail the address on file, so a forged POST buys
  # an attacker nothing but the rate limit.
  skip_forgery_protection only: :create

  before_action :discard_honeypot, only: :create

  rate_limit to: 5, within: 3.minutes, only: :create,
    with: -> { redirect_to claim_renewal_sent_path }

  layout "public_minimal"

  def create
    subscriber = Current.account.subscribers.confirmed
      .find_by(email_address: Subscriber.normalize_value_for(:email_address, params[:email_address]))
    if subscriber&.grants&.any?
      subscriber.grants.each(&:renew)
      MagnetMailer.renewal(subscriber).deliver_later
    end

    redirect_to claim_renewal_sent_path
  end

  # The "check your inbox" interstitial — same card whether anything was sent.
  def sent
  end

  private
    # Same pinned decoy field the static newsletter form uses; a filled value
    # is a bot, and it gets the same page a human does.
    def discard_honeypot
      redirect_to claim_renewal_sent_path if params[Subscriber::HONEYPOT_FIELD].present?
    end
end
