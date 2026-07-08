ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActionDispatch
  class IntegrationTest
    # Sign in by minting and redeeming a magic-link code (the real flow).
    def sign_in_as(user)
      get admin_verify_session_path(code: user.sign_in_codes.create!.plaintext)
    end
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Run a block with the magic-link registration policy temporarily overridden.
    def with_registration_policy(policy)
      config = Rails.configuration.x.authentication
      original = config.registration_policy
      config.registration_policy = policy
      yield
    ensure
      config.registration_policy = original
    end
  end
end
