# One saved state of an account's public-site design (the SiteDesigner's
# payload — axes + content blocks + escape valves). An account keeps exactly
# one `drafted` version (the working copy the designer edits and the preview
# host serves) and one `published` version (what production builds from);
# promoting archives the old live design, so the table doubles as design
# history and a rollback trail. The raw `data` blob is still validated by the
# SiteDesign value object — this model owns persistence and lifecycle, not
# the "is this design acceptable?" question.
class SiteDesignVersion < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: "User", optional: true

  enum :status, %w[ drafted published archived ].index_by(&:itself)

  # Newest first — the archived rows read as a history stack.
  scope :recent, -> { order(published_at: :desc, created_at: :desc) }
  # The revert trail the designer's History pane lists: retired versions,
  # newest save first (published_at only marks the ones that were once live).
  scope :history, -> { archived.order(created_at: :desc) }

  # Whether this version was ever the live production design — publishing
  # stamps published_at, and archiving keeps it.
  def was_live? = published_at.present?
end
