# A named source of subscribers: a BookFunnel promo, a newsletter swap, or the
# permanent link on your own site that every promo should be measured against.
# Deliberately generic — what this names is "where a reader came from", and only
# some of those are promotions in the marketing sense.
#
# Attribution runs on `ref`, the token a reader arrives carrying. Today that
# token is the last path segment of the BookFunnel landing page the partner
# reports in Subscriber#source_url (dl.bookfunnel.com/wzpbv5o1z2 -> wzpbv5o1z2),
# which BookFunnel mints per book-and-promo pair, so two promos featuring one
# book are two refs. A `?ref=` on this site's own signup form would feed the
# same column later without a migration — which is why the column isn't named
# for BookFunnel.
#
# A promotion with no ref is legitimate: a swap where the partner simply names
# you and readers type the URL leaves nothing to match on, and those readers are
# attributed by hand (Subscriber#attributed_by) or not at all.
class Promotion < ApplicationRecord
  belongs_to :account, default: -> { Current.account }
  belongs_to :creator, class_name: "User", default: -> { Current.user }

  # Nullify, never cascade: a promotion is a label on a reader, and deleting the
  # label must not touch the reader. (A nullified row keeps its attributed_by,
  # which means nothing without a promotion and which nothing reads without one.)
  has_many :subscribers, dependent: :nullify

  # Accepts whatever the author pastes — the whole landing-page URL, or the bare
  # code out of it.
  normalizes :ref, with: -> { Promotion.ref_from(it) }

  # Letters, digits and hyphens: what a partner's link code or a ?ref= token is
  # made of, and pointedly not the LIKE wildcards (% and _) that claim_arrivals
  # interpolates against.
  REF_FORMAT = /\A[a-z0-9-]+\z/

  validates :title, presence: true
  # Backed by the unique index on [account_id, ref].
  validates :ref, uniqueness: { scope: :account_id }, allow_nil: true,
                  format: { with: REF_FORMAT, message: "isn't a link or code we recognize" }

  scope :ordered, -> { order(shared_on: :desc, created_at: :desc) }

  # Naming a promotion is how its readers get attributed, so the ones who
  # arrived before it existed are adopted on save — register October's swap
  # three weeks late and its readers snap into place. Runs on a ref change too,
  # which is what fixing a typo in one needs to do.
  #
  # ref.present? is load-bearing, not defensive: clearing a ref would otherwise
  # send claim_arrivals in with a LIKE of "%%" and adopt every unattributed
  # reader on the site.
  after_save_commit :claim_arrivals, if: -> { saved_change_to_ref? && ref.present? }

  # The promotion a fresh arrival belongs to. Always reached through the
  # account (Current.account.promotions.matching(url)) so the lookup is scoped.
  def self.matching(source_url)
    ref = ref_from(source_url)
    find_by(ref: ref) if ref
  end

  # The token out of a landing-page URL, or a bare code handed over as-is.
  # Query strings and trailing slashes fall away with the path parse.
  #
  # Input that isn't a URL at all comes back as itself rather than as nil, so a
  # mistyped link fails validation with something the author can act on instead
  # of silently saving a promotion with no link.
  def self.ref_from(value)
    stripped = value.to_s.strip
    segment = begin
      URI.parse(stripped).path.to_s.split("/").last
    rescue URI::InvalidURIError
      nil
    end

    (segment || stripped).downcase.presence
  end

  # Tokens that have brought readers in but have no promotion yet — the index's
  # "name this" list, biggest first. Refs that differ only in URL shape (a
  # trailing slash, a query string) collapse onto one key.
  def self.unnamed_refs(account)
    account.subscribers.unattributed.where.not(source_url: [ nil, "" ])
      .group(:source_url).count
      .each_with_object(Hash.new(0)) do |(url, count), refs|
        # Only tokens shaped like one: a source_url too mangled to read a ref
        # out of is nothing an author could name.
        ref = ref_from(url)
        refs[ref] += count if ref&.match?(REF_FORMAT)
      end
      .sort_by { |_ref, count| -count }
  end

  def to_s = title

  private
    # Only unattributed readers, and only this account's. A partner's token is
    # unguessable enough that a suffix match can't collide, and `ref` is
    # validated to letters, digits and hyphens — none of which are LIKE
    # wildcards (% and _ can never appear in one).
    def claim_arrivals
      account.subscribers.unattributed
        .where("source_url LIKE ?", "%#{ref}%")
        .update_all(promotion_id: id)
    end
end
