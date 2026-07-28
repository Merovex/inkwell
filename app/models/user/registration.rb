# Registration plumbing. The gate is a valid join code (see Signup), not a
# policy switch; the first-user bootstrap is the Setup flow (SetupsController),
# which only runs when no users exist.
module User::Registration
  extend ActiveSupport::Concern

  class_methods do
    # Existing user for an address, normalizing it the same way we store it.
    def with_email_address(email_address)
      find_by(email_address: normalize_value_for(:email_address, email_address))
    end
  end
end
