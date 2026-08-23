# What the platform knows about an address across every site, reduced to the
# one question the send path asks: may this site mail this person? A thin
# reading of the Suppression ledger — no score, no cluster, no thresholds
# (ADR 0027). Every broadcast and drip send asks suppressed_for? before
# enqueueing; nothing else decides.
class Person::Reputation
  attr_reader :person

  def initialize(person)
    @person = person
  end

  # On the global list: hard-bounced, or complained against enough sites.
  def suppressed?
    Suppression.in_force_for.where(person:).exists?
  end

  # Unmailable by this site: globally suppressed, or suppressed for it alone.
  def suppressed_for?(account)
    Suppression.in_force_for(account).where(person:).exists?
  end
end
