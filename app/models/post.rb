# A version of a blog post — the first recordable on the spine. Rows are
# immutable once published (see Recordable#mutable?); access always goes
# through the Record, whose id is the public identity (/posts/:id).
class Post < ApplicationRecord
  include Recordable

  belongs_to :body

  enum :status, %w[ drafted scheduled published ].index_by(&:itself), default: :drafted

  validates :title, presence: true
  # Booking a past time would publish immediately (the job's wait_until is
  # already due). Checked on the transition version only — an existing
  # appointment naturally becomes past as its time arrives.
  validate :appointment_in_future, if: -> { event_scheduled? && new_record? }

  before_validation -> { self.body ||= Body.new }
  after_destroy :discard_orphaned_body

  # The current version of every live (untrashed) record — the rows the app
  # lists; superseded versions and trashed records never surface here.
  scope :current, -> { where(id: Record.active.posts.select(:recordable_id)) }

  # Pinned posts first (newest pin first), then newest by publish date —
  # drafts fall back to creation date so they sort among their peers.
  scope :feed_ordered, -> {
    order(Arel.sql("pinned_at DESC NULLS LAST, COALESCE(published_at, posts.created_at) DESC"))
  }

  def content
    body&.content
  end

  # Assigning content mints a fresh Body, so a successor built with a :content
  # change gets its own body while action-only successors share the old one.
  # Draft-mode edits go through #amend instead, which updates the body in place.
  def content=(html)
    self.body = Body.new(content: html)
  end

  def amend(**changes)
    html = changes.delete(:content)
    transaction do
      body.update!(content: html) if update(changes) && html
    end
    self
  end

  # A version is mutable until the world sees it — or is about to: scheduled
  # posts are "essentially drafts" until their publish time arrives.
  def mutable? = drafted? || scheduled?

  # Was any version of this post ever actually live? (Scheduled-but-never-
  # published doesn't count.) Governs retention and hard-delete eligibility.
  def ever_published?
    record.versions.where(status: :published).exists?
  end

  # Anything the world once saw is retained two years in the trash — legal
  # exposure outlives the unpublish button.
  def retention_period
    ever_published? ? 2.years : super
  end

  # First publish keeps an already-past published_at (republishing a fixed-up
  # post preserves its feed/permalink date); otherwise stamps now — which also
  # covers publishing a scheduled post early (the future date is discarded).
  # Reads the record's current version, not self — self may be superseded.
  # Any pending edits ride along as `changes` on the transition version.
  def publish(creator: Current.user, **changes)
    current = record.recordable
    record.revise(event: :published, status: :published, creator: creator,
      published_at: (current.published_at&.past? ? current.published_at : Time.current),
      **changes)
  end

  # Schedule: an event version holding the appointment in published_at; the
  # post stays mutable until Post::PublishLaterJob publishes it at that time.
  def schedule(at:, creator: Current.user, **changes)
    record.revise(event: :scheduled, status: :scheduled, published_at: at,
      creator: creator, **changes).tap do |version|
      Post::PublishLaterJob.set(wait_until: at).perform_later(record) if version.persisted?
    end
  end

  # Cancel the appointment: back to a plain draft. published_at clears — it
  # was never a real publish date, just the booking (the enqueued job no-ops
  # once the post is no longer scheduled).
  def unschedule(creator: Current.user, **changes)
    record.revise(event: :unscheduled, status: :drafted, published_at: nil,
      creator: creator, **changes)
  end

  def unpublish
    record.revise(event: :unpublished, status: :drafted)
  end

  def pin
    record.revise(event: :pinned, pinned_at: Time.current)
  end

  def unpin
    record.revise(event: :unpinned, pinned_at: nil)
  end

  private
    # Bodies are shared between versions; only delete one when its last
    # referencing version goes.
    def discard_orphaned_body
      body.destroy unless self.class.exists?(body_id: body_id)
    end

    def appointment_in_future
      errors.add(:base, "That scheduled time has already passed — pick a later one.") if published_at&.past?
    end
end
