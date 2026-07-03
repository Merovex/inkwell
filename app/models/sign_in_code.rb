# A single-use, short-lived magic-link code emailed to a user. The plaintext
# code is 8 capital letters shown to humans as "ABCD-EFGH" (26**8 permutations);
# only its SHA-256 digest is stored, so a leaked database row can't be replayed.
# The plaintext is generated on create and available on that record for the life
# of the object (never reloaded from the database).
class SignInCode < ApplicationRecord
  belongs_to :user

  EXPIRES_IN = 15.minutes
  ALPHABET = ("A".."Z").to_a.freeze
  LENGTH = 8

  attr_reader :plaintext

  before_create :generate

  scope :active, -> { where(consumed_at: nil).where(expires_at: Time.current..) }

  # Redeem a plaintext code (dashes/whitespace/casing forgiven). Consumes the
  # matching unexpired code and returns its user, or nil if nothing matches.
  def self.redeem(plaintext)
    canonical = normalize(plaintext)
    return unless canonical.match?(/\A[A-Z]{#{LENGTH}}\z/)

    if code = active.find_by(code_digest: digest(canonical))
      code.consume!
      code.user
    end
  end

  def self.normalize(plaintext)
    plaintext.to_s.gsub(/[^A-Za-z]/, "").upcase
  end

  def self.digest(canonical)
    Digest::SHA256.hexdigest(canonical)
  end

  # Group the plaintext into the human-facing "ABCD-EFGH" display form.
  def self.format(plaintext)
    normalize(plaintext).scan(/.{1,4}/).join("-")
  end

  def consume!
    update!(consumed_at: Time.current)
  end

  private

  def generate
    @plaintext = Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join
    self.code_digest = self.class.digest(@plaintext)
    self.expires_at ||= EXPIRES_IN.from_now
  end
end
