# The stable identity every piece of content lives behind (ADR 0006/0007).
# Holds what never changes (creator, threading, position) plus two cursors:
# recordable (the current version) and trashed_at (the cheap list filter —
# trash history itself lives in the version rows). Deliberately tenant-
# agnostic: host apps that need scoping add their own column on this spine.
class Record < ApplicationRecord
  include Boostable

  # Mention notifications sourced to this record (see Mentions); stamped
  # copies survive the record via nullify.
  has_many :notifications, as: :source, dependent: :nullify

  # Content types that may live in the envelope; grows as recordables are added.
  RECORDABLE_TYPES = %w[ Post Comment ChatLine Message Book Series Collection Author Drip Drop Site Pulse Beat Goal Tally Bulletin Page ]
  # Platform content belongs to the App itself, not any bucket — a NIL bucket
  # is its tenancy (originate with an explicit bucket: nil).
  PLATFORM_TYPES = %w[ Bulletin ].freeze

  delegated_type :recordable, types: RECORDABLE_TYPES, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }
  # Tenancy is stamped at birth and never changes: the bucket that owns this
  # record — an Account (the site) or a Circle. The active bucket is whichever
  # namespace set Current.bucket; account space leaves it unset, so we fall back
  # to Current.account (the site is always the default owner). Platform types
  # are the one exception — no bucket at all, and the default must decide that
  # HERE: `default:` fires whenever the association is nil, so an explicit
  # `bucket: nil` at create can never beat it.
  belongs_to :bucket, polymorphic: true, optional: true,
    default: -> { Current.bucket || Current.account unless PLATFORM_TYPES.include?(recordable_type) }
  validates :bucket, presence: true, unless: -> { PLATFORM_TYPES.include?(recordable_type) }

  # The public path of the types whose URL is their identity (Pages today).
  # Sparse: everything else leaves it NULL and keeps the id-first #to_slug.
  # One /about/ per bucket, enforced by a partial unique index — this
  # validation only exists to turn the collision into a message. Permanent
  # once set: renaming a page breaks every link that ever pointed at it, so
  # the answer is a new page, not a moved one.
  validates :slug, uniqueness: { scope: %i[ bucket_type bucket_id ] }, allow_nil: true
  validate :slug_is_permanent, on: :update

  # Self-referential threading: a comment's record will parent to the record it
  # comments on; same mechanism for any future child content.
  belongs_to :parent, class_name: "Record", optional: true
  has_many :children, class_name: "Record", foreign_key: :parent_id,
    inverse_of: :parent, dependent: :destroy

  # Store buy-links (books only in practice); live on the stable identity, not
  # the versioned recordable. See Distributor.
  has_many :distributors, dependent: :destroy

  # The one-time newsletter send of this record (posts only in practice). On the
  # stable identity so it survives edits; present ⇒ already broadcast. See Broadcast.
  has_one :broadcast, dependent: :destroy

  scope :active,  -> { where(trashed_at: nil) }
  scope :trashed, -> { where.not(trashed_at: nil) }
  scope :purgeable, -> { trashed.where(purge_after: ..Time.current) }
  # Archive is a separate axis from trash: a permanent, reversible set-aside
  # (no purge). `listed` is what the default lists show — neither trashed nor
  # archived; `archived` is the set-aside, still active so it can be reopened.
  scope :listed,   -> { active.where(archived_at: nil) }
  scope :archived, -> { active.where.not(archived_at: nil) }
  scope :posts, -> { where(recordable_type: "Post") }
  scope :comments, -> { where(recordable_type: "Comment") }
  scope :chat_lines, -> { where(recordable_type: "ChatLine") }
  scope :messages, -> { where(recordable_type: "Message") }
  scope :books, -> { where(recordable_type: "Book") }
  scope :series, -> { where(recordable_type: "Series") }
  scope :collections, -> { where(recordable_type: "Collection") }
  scope :authors, -> { where(recordable_type: "Author") }
  scope :drips, -> { where(recordable_type: "Drip") }
  scope :drops, -> { where(recordable_type: "Drop") }
  scope :goals, -> { where(recordable_type: "Goal") }
  scope :tickets, -> { where(recordable_type: "Ticket") }
  scope :tallies, -> { where(recordable_type: "Tally") }
  scope :bulletins, -> { where(recordable_type: "Bulletin") }
  scope :pages, -> { where(recordable_type: "Page") }

  before_destroy :destroy_versions

  # Birth of a record: the row must exist before its first version can carry
  # record_id, then the cursor points at that version — one transaction. The
  # record's creator is the first version's author, always. Child content
  # (comments) passes the record it hangs from as parent. Platform types get
  # their nil bucket from the bucket default above — by type, not by caller.
  def self.originate(version, parent: nil, slug: nil)
    transaction do
      create!(recordable_type: version.class.name, creator: version.creator, parent: parent, slug: slug).tap do |record|
        version.update!(record: record)
        record.update!(recordable: version)
      end
    end
  end

  # All versions, oldest first. One type per record for life, so the class
  # comes straight from the delegated type.
  def versions
    recordable_class.where(record_id: id).order(:id)
  end

  # The static-site rebuild trigger (docs/phase-2-static-serving.md §2.3):
  # a revision or trash/restore on a Site's public content re-publishes the
  # static build. Only record-row UPDATES fire — draft churn amends the
  # version row in place and never moves the cursor, so drafts don't build.
  # Mutable types (Site, Author) hook their own models for the same reason.
  #
  # Born-published content (create + publish in one transaction — e.g. the
  # posts controller's publish-at-create) commits as a CREATE, so the update
  # callback never fires; the create hook catches exactly that case. Types
  # without published? (Site at account birth) stay quiet.
  # Distinct method names — a second after_*_commit registering the same
  # method would silently replace the first. originate's create+update in one
  # transaction commits as a CREATE, so only the create hook sees new records.
  STATIC_SITE_TYPES = %w[ Site Post Book Series Collection Author Page ].freeze
  after_update_commit :schedule_site_build
  after_create_commit :schedule_site_build_if_born_published

  # Insert the next immutable version and repoint the cursor. Returns the
  # version (unsaved, with errors, when invalid — the cursor then stays put).
  def revise(event:, creator: Current.user, **changes)
    version = recordable.build_successor(event: event, creator: creator, **changes)
    transaction do
      update!(recordable: version) if version.save
    end
    version
  end

  # The whole save policy in one ladder (ADR 0007): a requested transition
  # wins (publish beats schedule beats unschedule), folding the edit into the
  # transition version; otherwise the regime rule — drafts mutate in place,
  # published content versions on every save.
  def save_edit(creator: Current.user, publish: false, schedule_at: nil, unschedule: false, **changes)
    if publish && !recordable.published?
      recordable.publish(creator: creator, **changes)
    elsif schedule_at
      recordable.schedule(at: schedule_at, creator: creator, **changes)
    elsif unschedule && recordable.scheduled?
      recordable.unschedule(creator: creator, **changes)
    elsif recordable.mutable?
      recordable.amend(**changes)
    else
      revise(event: :updated, creator: creator, **changes)
    end
  end

  # Live comments under this record — current versions only, oldest first
  # (record ids are creation-ordered; version ids aren't, once edits land).
  def comments
    Comment.where(id: children.active.comments.select(:recordable_id))
      .includes(:rich_text_content, creator: { avatar_attachment: :blob },
        record: [ :parent, { boosts: { creator: { avatar_attachment: :blob } } } ])
      .order(:record_id)
  end

  # A pretty, id-first permalink slug used by the public site: the id followed
  # by the parameterized title (e.g. "3-my-upcoming-book-title"). The id is all
  # a lookup needs — String#to_i drops the tail, so Record.find works with the
  # whole slug — which keeps links stable when a title is later edited. Records
  # with no title (comments, chat lines) slug to just the id.
  #
  # A not-yet-published recordable gets an extra #preview_key segment, so an
  # early (e.g. broadcast-before-publish) link resolves while the bare id 404s —
  # a timing gate, not security (see BlogController#show). Once published the key
  # drops and the clean slug takes over.
  def to_slug
    return slug if slug.present?

    base = [ id, recordable&.try(:title).presence&.parameterize ].compact.join("-")
    recordable.try(:published?) == false ? "#{base}-#{preview_key}" : base
  end

  # Crockford Base32, lowercased (no i/l/o/u) — legible in a URL.
  PREVIEW_ALPHABET = "0123456789abcdefghjkmnpqrstvwxyz"

  # A short, unguessable-without-the-secret slug segment for pre-publish links,
  # derived from the id via HMAC so there's nothing to store. Five chars (~33M)
  # is plenty to keep fishers off a post that's going public shortly anyway.
  def preview_key
    mac = OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "blog-preview:#{id}")
    mac.bytes.first(5).map { |byte| PREVIEW_ALPHABET[byte % 32] }.join
  end

  def trashed? = trashed_at.present?
  def archived? = archived_at.present?

  # Who may change vs. moderate this record, bucket-agnostically. Editing (the
  # words) is the author's alone; moderating (archive, trash) is the author OR
  # the bucket's owner — the circle owner, or an account admin. So a bucket
  # owner always has a moderation override, whatever the content type.
  def editable_by?(user) = user.present? && creator_id == user.id
  def moderatable_by?(user) = editable_by?(user) || bucket&.moderated_by?(user)

  # Set aside without deleting: a tracked event, kept indefinitely (no purge
  # deadline), reversible via #unarchive. Orthogonal to trash — the default
  # lists (Record.listed) hide archived content; the archived view surfaces it.
  def archive
    transaction do
      revise(event: :archived)
      update! archived_at: Time.current
    end
  end

  def unarchive
    transaction do
      revise(event: :unarchived)
      update! archived_at: nil
    end
  end

  # Staged deletion, always on the history regardless of draft/published.
  # Recoverable until the purge deadline: the recordable's retention_period
  # (30 days; 2 years for ever-published content — legal hold).
  def trash
    transaction do
      revise(event: :trashed)
      update! trashed_at: Time.current, purge_after: recordable.retention_period.from_now
    end
  end

  def restore
    transaction do
      revise(event: :restored)
      update! trashed_at: nil, purge_after: nil
    end
  end

  private
    def slug_is_permanent
      errors.add(:slug, "can't be changed once a page is live") if slug_changed? && slug_was.present?
    end

    def destroy_versions
      versions.find_each(&:destroy)
    end

    def schedule_site_build
      return unless bucket_type == "Account" && STATIC_SITE_TYPES.include?(recordable_type)
      SiteBuildJob.schedule(bucket)
    end

    # Born-published content (create + publish in one transaction, e.g. the
    # posts controller's publish-at-create) builds; drafts stay quiet, as do
    # types without published? (Site at account birth).
    def schedule_site_build_if_born_published
      schedule_site_build if recordable.try(:published?)
    end
end
