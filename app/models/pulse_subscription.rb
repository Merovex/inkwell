# A member's opt-in to a circle's Pulse — they'll be asked and can beat back.
# A plain join (like CircleMembership), keyed to the pulse's stable Record id.
# Only circle members may subscribe; a member removes their own row to opt out.
class PulseSubscription < ApplicationRecord
  belongs_to :pulse_record, class_name: "Record"
  belongs_to :user

  validates :user_id, uniqueness: { scope: :pulse_record_id }
  validate :respondent_is_a_circle_member

  private
    def respondent_is_a_circle_member
      circle = pulse_record&.bucket
      return if circle.is_a?(Circle) && circle.member?(user)

      errors.add(:user, "must be a member of the circle")
    end
end
