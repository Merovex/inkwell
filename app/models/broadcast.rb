# A one-time email send of a post to confirmed subscribers (HEY World: a
# published post can also go out as the newsletter). Lives on the post's Record
# — the stable identity — so it's independent of the post's versions, and the
# unique index on record_id means a post can be broadcast exactly once. Creating
# the row is the guard; PostBroadcastJob then fans out and stamps the outcome.
#
# The issue itself is frozen onto the row when the fan-out starts (#issue!):
# every recipient's email is built from that one copy, and it's what the
# public archive (/newsletters/<title>-<slug>, IssuesController) shows — a
# record of what went out, untouched by later edits to the post. Sluggable
# anchors that link, so it never moves.
class Broadcast < ApplicationRecord
  include Sluggable

  belongs_to :record
  has_many :deliveries, class_name: "BroadcastDelivery", dependent: :destroy

  validates :record_id, uniqueness: true

  scope :issued, -> { where.not(issued_at: nil) }

  # The post being sent (the record's current version).
  def post
    record.recordable
  end

  def sent?
    sent_at.present?
  end

  # Booked to send later and not yet sent — the wait_until job is pending.
  def scheduled?
    scheduled_at.present? && !sent?
  end

  # The archive's title half of to_param.
  def to_s
    archive_title
  end

  # What the archive page shows: the frozen issue once the send has started;
  # before that (a scheduled send, whose link may already be with a promo
  # partner), the issue as it stands, rendered live — so edits until the send
  # still show, and the page settles on exactly what went out.
  def archive_title
    issued? ? issue_title : post&.title
  end

  def archive_html
    issued? ? issue_html : render_issue
  end

  def issued?
    issued_at.present?
  end

  # Freeze the issue exactly as the newsletter sends it — title plus the body
  # with the tip-in spliced in — once. Rendered with the mailer's URL options,
  # so embedded images point at the app host (where Active Storage answers),
  # never the static tenant host the archive is served from.
  def issue!(at: Time.current)
    return if issued?

    update!(issue_title: post.title, issue_html: render_issue, issued_at: at)
  end

  # Where this broadcast is in its life, for the dashboard.
  def state
    return :scheduled if scheduled?
    return :sent if sent?
    :sending
  end

  # Rates for the dashboard; nil when there's no denominator yet (shown as "—").
  # Opens/clicks are over *delivered*, the usual newsletter convention.
  def delivery_rate = rate(delivered_count, recipients_count)
  def open_rate     = rate(opened_count, delivered_count)
  def click_rate    = rate(clicked_count, delivered_count)

  private
    def render_issue
      url_options = Rails.application.config.action_mailer.default_url_options.to_h
      renderer = ApplicationController.renderer.new(
        http_host: [ url_options[:host], url_options[:port] ].compact.join(":"),
        https: Rails.application.config.force_ssl)

      ActionText::Content.with_renderer(renderer) { post.email_content.to_s }
    end

    def rate(numerator, denominator)
      denominator.to_i.zero? ? nil : numerator.to_f / denominator
    end
end
