# Consent evidence a partner integration sends with a pre-consented opt-in
# (BookFunnel via the Sendy-compatible endpoint): where the reader was when
# they ticked the box, whether that place puts them under GDPR, and the page
# that asked. The IP already had a home in consent_ip; these three did not, and
# BookFunnel's own docs are explicit that a field with no home is thrown away.
#
# On the subscriber row, beside consent_ip, rather than on the append-only
# event: the current-state row is what the roster, the detail card and a
# data-subject request read. A later re-subscribe overwrites them, same as
# consent_ip — the per-act IP still lands on the event.
class AddConsentEvidenceToSubscribers < ActiveRecord::Migration[8.2]
  def change
    add_column :subscribers, :country_code, :string
    add_column :subscribers, :gdpr_country, :boolean
    add_column :subscribers, :source_url, :string
  end
end
