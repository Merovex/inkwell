# A platform announcement — root staff speaking to every user (the Basecamp
# bulletin): title + rich body, the full Publishable regime (draft →
# scheduled → published, versioned). Lives on the spine with a NIL bucket:
# platform content belongs to the App, not any Account or Circle
# (Record::PLATFORM_TYPES). First publish rings every user's bell —
# bulletin_published is deliberately not in Notification::EMAILED, so no
# email — via BulletinAnnounceJob, whatever the path there (Publish button or
# the scheduler firing Record::PublishLaterJob).
class Bulletin < ApplicationRecord
  include Publishable

  # Every publish transition (and every edit of published content) creates a
  # published version row; the job dedupes on existing notifications so only
  # the FIRST publish announces.
  after_create_commit :announce, if: :published?

  private
    def announce
      BulletinAnnounceJob.perform_later(record)
    end
end
