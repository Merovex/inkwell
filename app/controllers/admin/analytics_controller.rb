# Public-site traffic at a glance (Ahoy). Domain-admin only, read-only. Visits
# and page views are collected client-side (ahoy.js), so this reflects
# edge-cached loads too. Per-page detail lives in the visits' landing pages;
# richer drill-down can come later.
class Admin::AnalyticsController < Admin::BaseController
  WINDOW = 30.days

  def show
    since = WINDOW.ago
    @visits = Ahoy::Visit.where(started_at: since..).count
    # Unique people (well, browsers): ahoy's long-lived visitor token, not visits.
    @visitors = Ahoy::Visit.where(started_at: since..).distinct.count(:visitor_token)
    @views  = Ahoy::Event.where(name: "$view", time: since..).count
    @landing_pages = top(Ahoy::Visit.where(started_at: since..).where.not(landing_page: nil), :landing_page)
    @referrers = top(Ahoy::Visit.where(started_at: since..).where.not(referring_domain: [ nil, "" ]), :referring_domain)

    # Geography (unique visitors, not visits) — filled by the GeoLite2 geocode
    # job; empty until storage/geoip/ has the database. Region is grouped with
    # its country so "Texas" and, say, "Bavaria" don't collide.
    geographed = Ahoy::Visit.where(started_at: since..).where.not(country: [ nil, "" ])
    @countries = top(geographed, :country, distinct: :visitor_token)
    @regions = top(geographed.where.not(region: [ nil, "" ]), [ :region, :country_code ], distinct: :visitor_token)
    # Choropleth data (all rows, no top-N): world by ISO country code, and US
    # by state name — the map view shows states while the audience is US-heavy.
    @geo_map = geographed.where.not(country_code: [ nil, "" ])
      .group(:country_code).distinct.count(:visitor_token)
    @us_states = geographed.where(country_code: "US").where.not(region: [ nil, "" ])
      .group(:region).distinct.count(:visitor_token)
  end

  private
    def top(scope, column, limit: 10, distinct: nil)
      if distinct
        scope.group(column).order(Arel.sql("COUNT(DISTINCT #{distinct}) DESC"))
          .limit(limit).distinct.count(distinct)
      else
        scope.group(column).order(Arel.sql("COUNT(*) DESC")).limit(limit).count
      end
    end
end
