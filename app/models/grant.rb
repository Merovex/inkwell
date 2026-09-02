# One subscriber's key to one reader magnet — minted when a magnet-bearing
# Drop is sent (Magnet#grant_to), one row per pair for life. The claim link is
# a signed expiring token, no token column: "send me a new link" just mints a
# fresh token for the same row, and nothing stored can leak.
#
# Like the subscriber confirmation token, the claim token deliberately folds
# in no use-count — email scanners prefetch links, so the claim page GET must
# stay resolvable however many times it's fetched. Only the download POST
# spends anything, and the cap guards casual mass-fetching, not determined
# piracy (that fight isn't winnable with a counter).
class Grant < ApplicationRecord
  TOKEN_LIFETIME = 30.days
  DOWNLOAD_LIMIT = 5

  belongs_to :magnet
  belongs_to :subscriber

  # Plain timestamp rows, no callbacks — delete straight through.
  has_many :downloads, dependent: :delete_all

  generates_token_for :claim, expires_in: TOKEN_LIFETIME

  def account = magnet.account

  def claim_token = generate_token_for(:claim)

  # Both renewal doors end here — the reader's own "send me a new link" and
  # staff re-sending from the roster. A fresh token alone is no help to a
  # reader whose cap is spent: the new link opens the same expired page they
  # wrote in about. So a renewal moves the allowance window forward instead of
  # deleting Downloads, which are the audit trail, not a counter.
  def renew = update!(renewed_at: Time.current)

  def exhausted? = downloads.where(created_at: allowance_since..).count >= DOWNLOAD_LIMIT

  private
    # Never nil: a grant that has never been renewed counts from its own birth.
    def allowance_since = renewed_at || created_at
end
