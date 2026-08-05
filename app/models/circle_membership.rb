# One person's seat in a Circle. Separate from AccountUser: a circle's roles
# (owner/member) and size cap are its own, and its members are people who may
# belong to no shared account at all. The unique [circle_id, user_id] index is
# the load-bearing constraint; the validation just gives a friendly error.
class CircleMembership < ApplicationRecord
  # The inviter's "accepted" bell row keeps its stamped copy if the seat goes.
  has_many :notifications, as: :source, dependent: :nullify
  ROLES = %w[ owner member ].freeze

  belongs_to :circle
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :circle_id }
  validate :within_member_limit, on: :create

  private
    # Refuse a new seat once the circle is full (its member_limit or, always,
    # the hard cap). The owner's own seat is created with the circle (count 0
    # at that point), so it always fits.
    def within_member_limit
      errors.add(:base, "Circle is full") if circle&.full?
    end
end
