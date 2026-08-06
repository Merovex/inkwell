ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActionDispatch
  class IntegrationTest
    # Sign in by minting and redeeming a magic-link code (the real flow).
    def sign_in_as(user)
      get verify_session_path(code: user.sign_in_codes.create!.plaintext)
    end
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Mirror the middleware's resolution: tests run inside the fixture
    # account unless they say otherwise (Current resets between tests).
    setup { Current.account = accounts(:merovex) }
  end
end
