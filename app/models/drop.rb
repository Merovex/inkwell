# One email in a Drip's sequence — a recordable, like Comment: its Lexxy body is
# versioned and every edit lands as a new version. Ordered within the Drip by its
# Record.position; delay_days is the absolute send offset (in days) from the
# subscriber's confirmed_at, so 0 means "right after confirmation".
class Drop < ApplicationRecord
  include Recordable

  has_rich_text :body

  validates :subject, presence: true
  validates :body, presence: true
  validates :delay_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Like Comment: earlier subscribers may already have received this email, so
  # every edit is a tracked version rather than an in-place amend.
  def mutable? = false

  # dup copies scalar columns but not the Action Text association; carry the body
  # forward on action-only versions (trash/restore) so the cursor keeps its text.
  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.body = body.body unless changes.key?(:body)
    end
  end

  # When this Drop should reach a given subscriber: absolute offset from the
  # stream's enrollment (their confirmed_at).
  def send_at_for(stream)
    stream.enrolled_at + delay_days.days
  end
end
