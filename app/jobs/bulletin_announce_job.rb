# Rings every user's bell for a freshly published Bulletin — except the
# author's (your own actions never notify you). Bell-only by construction:
# bulletin_published isn't in Notification::EMAILED, so the digest mailer
# never picks these up. Idempotent: a bulletin that already announced (edits
# of published content also commit published version rows) stays quiet, as
# does one unpublished before the job ran.
class BulletinAnnounceJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  def perform(record)
    Current.allowing_unscoped_tenancy do
      return unless record.recordable.try(:published?)
      return if Notification.where(source: record, kind: :bulletin_published).exists?

      User.where.not(id: record.creator_id).find_each do |user|
        Notification.deliver(record, to: user, kind: "bulletin_published")
      end
    end
  end
end
