# A support ticket — the App's help desk. Opened in-app from the user menu
# (no mail-in; the requester IS a User) and bucketed to the requester, the
# Goals pattern: your support history travels with you. The thread underneath
# is plain Comments on the spine — identical shape to a forum Message — so
# mentions, reply notifications, and the whole comment UI apply unchanged.
# Immutable like a Comment: every status change is a revision, an audit trail
# for free.
class Ticket < ApplicationRecord
  include Recordable

  # open → needs staff · pending → waiting on the requester ·
  # resolved → fixed (auto-closes after RESOLVED_TTL) · closed → done
  STATUSES = %w[ open pending resolved closed ].freeze
  RESOLVED_TTL = 1.week

  enum :status, STATUSES.index_by(&:itself), default: :open

  has_rich_text :content

  validates :title, presence: true
  validates :content, presence: true

  def mutable? = false

  # Carry the opening message and the resolved stamp across action-only
  # revisions — a status flip must never lose the requester's words.
  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.content = content.body unless changes.key?(:content)
      if changes.key?(:status)
        version.resolved_at = changes[:status].to_s == "resolved" ? Time.current : nil
      end
    end
  end
end
