# Which promotion sent this reader, alongside the rest of the arrival evidence
# already on the row (source, source_url, consent_ip, country_code) rather than
# in a table of its own — the Subscriber IS the record joining a Person to an
# Account, and how they got there is one of its facts.
#
# attributed_by is nil in the ordinary case and means nobody claimed this: the
# promotion was matched from the token the partner reported. Set, it names the
# admin who attributed the reader by hand. That one column is the difference
# between a number that was measured and one that was asserted, with no flag to
# keep in sync.
class AddPromotionToSubscribers < ActiveRecord::Migration[8.2]
  def change
    add_reference :subscribers, :promotion, foreign_key: true
    add_reference :subscribers, :attributed_by, foreign_key: { to_table: :users }
  end
end
