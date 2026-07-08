# One line in the chat — the third recordable on the spine, and the first
# with no parent besides posts (the install has a single room, so a line
# hangs off nothing). Like Comment: public the instant it's saved, so no
# draft regime and every edit would land as a tracked version. Rich text
# lives on the version directly (Action Text).
class ChatLine < ApplicationRecord
  include Recordable

  has_rich_text :content

  validates :content, presence: true

  # The room's transcript: current versions only, oldest first (record ids
  # are creation-ordered; version ids aren't, once edits land).
  def self.transcript
    where(id: Record.active.chat_lines.select(:recordable_id))
      .includes(:rich_text_content, creator: { avatar_attachment: :blob },
        record: { boosts: { creator: { avatar_attachment: :blob } } })
      .order(:record_id)
  end

  # Never mutable: the room saw it the moment it was said.
  def mutable? = false

  # dup copies columns but not the Action Text association; carry the text
  # forward on action-only versions (trash, restore) so the cursor never
  # lands on a blank body.
  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.content = content.body unless changes.key?(:content)
    end
  end
end
