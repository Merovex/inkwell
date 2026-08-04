# One member's answer to a Pulse occurrence — a "beat" of the check-in. A
# recordable whose Record parents to the Pulse's Record (the same threading
# Comments use), owned by the circle bucket. Rich text, and immutable like a
# comment: every edit lands as a tracked version. The author is the record's
# creator; asked_on marks which occurrence it answers.
class Beat < ApplicationRecord
  include Recordable

  has_rich_text :content

  validates :content, presence: true
  validates :asked_on, presence: true

  # Never amended in place — the circle sees a beat from its first save, so an
  # edit is a new version (see Comment for the same choice).
  def mutable? = false

  # dup copies columns but not the Action Text association; carry the text
  # forward on action-only versions so the cursor never lands on a blank body.
  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.content = content.body unless changes.key?(:content)
    end
  end
end
