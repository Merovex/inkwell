# A post on a circle's message board — a recordable on the spine, owned by the
# Circle (bucket) its record carries. Like Comment/ChatLine: never mutable, so
# every edit lands as a tracked version; rich text lives on the version. Adds a
# title, because a board reads as titled threads rather than a running stream.
class CircleMessage < ApplicationRecord
  include Recordable

  has_rich_text :content

  validates :content, presence: true

  def mutable? = false

  def title_or_default = title.presence || "Untitled"

  # dup copies columns but not the Action Text association; carry the text
  # forward on action-only versions (trash, restore) so the cursor never lands
  # on a blank body.
  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.content = content.body unless changes.key?(:content)
    end
  end
end
