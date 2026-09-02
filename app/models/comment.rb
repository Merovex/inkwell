# A comment on another record (a Post today) — the second recordable on the
# spine. Its Record parents to the record it comments on. No title, no status:
# a comment is public the instant it's saved, so there is no draft regime and
# every edit is a tracked version. Rich text lives on the version directly
# (Action Text), not behind a shared Body — comments don't need Post's
# body_id-comparison trick for the history feed.
class Comment < ApplicationRecord
  include Recordable

  has_rich_text :content

  validates :content, presence: true

  # Live wall: any thread change re-broadcasts the parent card's comment
  # count — creates, edits, AND trash/restore all commit new version rows, so
  # this one hook covers them (the recount reads live records, not versions).
  # Circle walls only; the count element is absent elsewhere and the replace
  # would no-op anyway.
  after_create_commit :broadcast_count_to_wall

  # Never mutable: the world sees a comment from its first save, so every
  # edit lands as a new version (see CommentsController#update).
  def mutable? = false

  # dup copies columns but not the Action Text association; carry the text
  # forward on action-only versions (trash, restore) so the cursor never
  # lands on a blank body.
  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.content = content.body unless changes.key?(:content)
    end
  end

  private
    def broadcast_count_to_wall
      parent = record&.parent
      return unless parent && parent.bucket_type == "Circle"
      broadcast_replace_later_to [ parent.bucket, :wall ],
        target: ActionView::RecordIdentifier.dom_id(parent, :wall_comments),
        partial: "circles/walls/comment_count",
        locals: { record: parent, count: parent.comments.size }
    end
end
