# Move the standing pages off the Site row and onto the spine: every existing
# account gets the four Pages (Page::MANDATORY), carrying whatever it had
# authored in System settings — description → /about/, privacy_policy →
# /privacy/, terms → /terms/. An account that never wrote one gets
# Page::Starter's copy instead, since these publish immediately and a live
# blank page is worse than a generic one. The newsletter page starts empty;
# its band carries its own defaults.
#
# The legacy rich-text rows are deliberately left in place (a one-way data
# move should never destroy the copy it read), just unreferenced: Site's
# has_rich_text declarations are gone, so nothing reads them after this. They
# are read here through ActionText directly for exactly that reason.
#
# Idempotent — an account that already has a page at a slug keeps it.
class SeedPagesFromSiteSettings < ActiveRecord::Migration[8.2]
  LEGACY = { "about" => "description", "privacy" => "privacy_policy", "terms" => "terms" }.freeze

  def up
    Account.find_each do |account|
      site_id = Record.where(bucket: account, recordable_type: "Site").pick(:recordable_id)

      Page::MANDATORY.each do |slug, title|
        next if Record.where(bucket: account, slug: slug).exists?

        page = Page.new(title: title, creator: account.owner,
          status: :published, published_at: Time.current,
          content: legacy_html(site_id, LEGACY[slug]).presence || Page::Starter.html_for(slug, account))
        # ::Current — inside a migration, a bare `Current` resolves to
        # ActiveRecord::Migration::Current, the versioned migration base class.
        ::Current.with_account(account) { Record.originate(page, slug: slug) }
      end
    end
  end

  # Reversal drops the pages (and their bodies, through the record cascade);
  # the legacy rich text is still on the Site rows, so nothing is lost.
  def down
    Record.where(recordable_type: "Page").find_each(&:destroy)
  end

  private
    def legacy_html(site_id, name)
      return if site_id.blank? || name.blank?

      ActionText::RichText.find_by(record_type: "Site", record_id: site_id, name: name)&.body&.to_s
    end
end
