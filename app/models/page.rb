# A standing page of the public site — About, Privacy, Terms, and the
# invitation above the newsletter signup. A recordable on the spine (ADR
# 0007), so a page draws the same draft/publish regime and version history as
# a post; what makes it a page is that its URL is fixed.
#
# The slug is NOT here. A page's path is its identity — links and search
# rankings hang off it — so it lives on the Record beside creator and bucket,
# set at birth and never edited, with a per-account unique index behind it.
# The title, by contrast, is just words on the page and the author may
# rewrite it whenever.
#
# Every account is seeded with the four at creation (Account#seed_pages) and
# none can be deleted: a site without a privacy page is a site with a broken
# footer link.
class Page < ApplicationRecord
  include Publishable

  # slug => the title the page is born with.
  MANDATORY = {
    "about" => "About",
    "privacy" => "Privacy Policy",
    "terms" => "Terms of Service",
    "newsletter" => "Newsletter"
  }.freeze

  # The public path, off the spine: /about/, /privacy/.
  def slug = record&.slug

  # Backend URLs read /admin/pages/about. Posts key on the record id because a
  # retitling moves their slug; a page's slug is permanent, so it's the
  # friendlier handle in the admin too.
  def to_param = slug
end
