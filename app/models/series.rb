# A book series — a recordable on the spine, Publishable exactly like Post
# (drafts mutate in place, published content versions on every save,
# scheduling via an event version + job). Its books are the Installment join,
# keyed by Record id so memberships survive versioning (see Installable).
class Series < ApplicationRecord
  include Publishable
  include Authored
  include Installable

  # Where the run stands, for the shelf band: planned → in progress → complete.
  # (Distinct from `status`, which is the publish state of this record.)
  enum :state, %w[planned in_progress complete].index_by(&:itself), default: "in_progress"

  # Band label + badge tone.
  def state_label = state.humanize
  def state_variant = { "complete" => "accent", "in_progress" => "warning" }[state] # else neutral
end
