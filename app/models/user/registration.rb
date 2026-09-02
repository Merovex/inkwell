# Registration plumbing. The gate is a valid join code (see Signup), not a
# policy switch; the first-user bootstrap is the Setup flow (SetupsController),
# which only runs when no users exist.
module User::Registration
  extend ActiveSupport::Concern

  included do
    # Every user gets a name at birth — a handle derived from their email —
    # so nothing ever has to fall back to showing the address itself.
    before_validation :assign_default_name, on: :create
  end

  class_methods do
    # Existing user for an address, normalizing it the same way we store it.
    def with_email_address(email_address)
      find_by(email_address: normalize_value_for(:email_address, email_address))
    end

    # Handle from the email's local part ("ben.wilson+tag@x.com" → "ben.wilson"),
    # made unique social-media style: on collision, append a 4-digit
    # discriminator ("ben.wilson4821") and re-roll until free. The unique index
    # on users.name backstops the (rare) race between check and insert.
    def generate_handle(email_address)
      base = email_address.to_s.split("@").first.to_s.split("+").first
               .downcase.gsub(/[^a-z0-9._]/, "")
      base = "member" if base.blank?
      handle = base
      handle = "#{base}#{rand(1000..9999)}" while where("LOWER(name) = ?", handle).exists?
      handle
    end
  end

  private
    def assign_default_name
      self.name = self.class.generate_handle(email_address) if name.blank?
    end
end
