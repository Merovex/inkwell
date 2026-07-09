# Public-site traffic at a glance (Ahoy). Domain-admin only, read-only. Visits
# and page views are collected client-side (ahoy.js), so this reflects
# edge-cached loads too. Per-page detail lives in the visits' landing pages;
# richer drill-down can come later.
class Admin::AnalyticsController < ApplicationController
  include AdminOnly

  WINDOW = 30.days

  def show
    since = WINDOW.ago
    @visits = Ahoy::Visit.where(started_at: since..).count
    @views  = Ahoy::Event.where(name: "$view", time: since..).count
    @landing_pages = top(Ahoy::Visit.where(started_at: since..).where.not(landing_page: nil), :landing_page)
    @referrers = top(Ahoy::Visit.where(started_at: since..).where.not(referring_domain: [ nil, "" ]), :referring_domain)
  end

  private
    def top(scope, column, limit: 10)
      scope.group(column).order(Arel.sql("COUNT(*) DESC")).limit(limit).count
    end
end
