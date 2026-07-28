# A rotatable, multi-use invite code owned by a user (root-only until the
# open-beta switch flips — see User#can_invite?). Deliberately NOT called an
# invitation: that term is reserved for future per-person invites (newsletter,
# circles). Modeled on Fizzy's Account::JoinCode, but ours admits you to the
# platform, and it belongs to the inviter — so abuse traces to whoever vouched
# (users.inviter_id), and rotation burns one inviter's code, nobody else's.
class JoinCode < ApplicationRecord
  CODE_LENGTH = 8

  belongs_to :user

  before_validation :assign_code, on: :create
  validates :code, presence: true, uniqueness: true

  # Crockford-normalized lookup: case-insensitive, I/L→1, O→0, and any
  # dash/space grouping the invitee typed is stripped.
  def self.redeem(input)
    find_by(code: Sluggable.normalize(input.to_s.gsub(/[^0-9a-zA-Z]/, "")))
  end

  # Kill the current code for everyone holding it; hand the owner a fresh one.
  def rotate!
    update!(code: self.class.generate_code, rotated_at: Time.current)
  end

  def self.generate_code
    SecureRandom.alphanumeric(CODE_LENGTH, chars: Sluggable::CROCKFORD_32.chars)
  end

  # Human-friendly display: ABCD-EFGH.
  def formatted
    code.scan(/.{1,4}/).join("-")
  end

  private
    def assign_code
      self.code ||= self.class.generate_code
    end
end
