# An author's request for a copy of their site: every post, page, book,
# newsletter, and drip as HTML to read, content.json as the complete record,
# wordpress.xml to move with, and the subscriber list as CSV (Export::Archive
# assembles it). A recordable bucketed to the Account, so the spine gives us
# who asked and when. Mutable like Tally — a build stamps its own row rather
# than churning versions.
#
# The zip holds the subscriber list, so it is short-lived: downloadable for
# RETENTION after the request, then destroyed by ExportExpiryJob.
class Export < ApplicationRecord
  include Recordable

  RETENTION = 7.days

  has_one_attached :archive

  enum :status, %w[ pending built failed ].index_by(&:itself), default: :pending

  scope :current, -> { where(id: Record.active.where(recordable_type: name).select(:recordable_id)) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :expired, -> { where(created_at: ..RETENTION.ago) }

  # One build at a time per site: a second request while one is underway
  # returns nil instead of queueing a duplicate. A pending row older than
  # STALLED_AFTER lost its worker and no longer blocks a fresh request.
  STALLED_AFTER = 1.hour

  def self.request(account, by: Current.user)
    return if account.exports.pending.exists?(created_at: STALLED_AFTER.ago..)

    new(creator: by).tap do |export|
      Record.originate(export)
      ExportJob.perform_later(export)
    end
  end

  def mutable? = true

  def account = record.bucket

  # Counted from the request, not the build, so the sweep (scope :expired)
  # also clears a build that failed or never finished.
  def expires_at = created_at + RETENTION
  def downloadable? = built? && archive.attached? && expires_at.future?

  # Assemble the zip, attach it, and tell the requester. A failure is stamped
  # on the row (the page shows it) and re-raised for Honeybadger.
  def build!
    Export::Archive.new(account).build do |path|
      archive.attach(io: File.open(path), filename: archive_filename, content_type: "application/zip")
    end
    update!(status: :built, completed_at: Time.current)
    ExportMailer.ready(self).deliver_later
  rescue
    update!(status: :failed)
    raise
  end

  def record_download!
    increment!(:downloads_count, touch: :last_downloaded_at)
  end

  private
    def archive_filename
      "#{account.handle.presence || account.slug}-export-#{created_at.to_date.iso8601}.zip"
    end
end
