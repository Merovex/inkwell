require "test_helper"

# Fail-closed server-side Turnstile verification (bot-protection plan). The
# suite has no HTTP stubbing, so the network path isn't exercised — the
# boundary logic is: everything short of an affirmative siteverify success is
# unverified, and a blank token never reaches the network at all.
class TurnstileVerifierTest < ActiveSupport::TestCase
  test "unprovisioned, everything passes — the widget and the check switch on together" do
    assert_nil TurnstileVerifier.secret_key_for(accounts(:merovex)), "test env must not carry a turnstile secret"
    assert TurnstileVerifier.new(nil).verified?
  end

  test "provisioned, a missing token fails closed before any network call" do
    with_turnstile_secret "server-side-secret" do
      assert_not TurnstileVerifier.new(nil).verified?
      assert_not TurnstileVerifier.new("").verified?
    end
  end

  test "the account's own widget keys beat the shared fallback pair" do
    accounts(:merovex).update!(turnstile_site_key: "sk-own", turnstile_secret_key: "secret-own")

    with_turnstile_secret "shared-secret" do
      assert_equal "secret-own", TurnstileVerifier.secret_key_for(accounts(:merovex))
      assert_equal "sk-own", TurnstileVerifier.site_key_for(accounts(:merovex))
    end
    # And with no account in play, the shared pair still answers.
    with_turnstile_secret "shared-secret" do
      assert_equal "shared-secret", TurnstileVerifier.secret_key_for(nil)
    end
  end

  private
    def with_turnstile_secret(secret)
      original = Rails.configuration.x.turnstile_secret_key
      Rails.configuration.x.turnstile_secret_key = secret
      yield
    ensure
      Rails.configuration.x.turnstile_secret_key = original
    end
end
