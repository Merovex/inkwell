require "test_helper"

# The Worker-proxied tenant host restore: X-Forwarded-Host is rewritten by the
# proxy hops in front of Rails, so the Worker sends X-Island-Host and this
# middleware copies it back — but only on the island-auth secret, so nobody
# can spoof a tenant host at the origin.
class IslandHostRewriterTest < ActiveSupport::TestCase
  test "restores the tenant host when the island-auth secret validates" do
    with_island_auth_secrets [ "edge-secret" ] do
      env = call_with("HTTP_X_ISLAND_HOST" => "merovex.press", "HTTP_X_ISLAND_AUTH" => "edge-secret")
      assert_equal "merovex.press", env["HTTP_X_FORWARDED_HOST"]
    end
  end

  test "a wrong or absent secret leaves the host alone" do
    with_island_auth_secrets [ "edge-secret" ] do
      env = call_with("HTTP_X_ISLAND_HOST" => "merovex.press", "HTTP_X_ISLAND_AUTH" => "guess")
      assert_nil env["HTTP_X_FORWARDED_HOST"]

      env = call_with("HTTP_X_ISLAND_HOST" => "merovex.press")
      assert_nil env["HTTP_X_FORWARDED_HOST"]
    end
  end

  test "unprovisioned, the rewrite is off entirely" do
    env = call_with("HTTP_X_ISLAND_HOST" => "merovex.press", "HTTP_X_ISLAND_AUTH" => "anything")
    assert_nil env["HTTP_X_FORWARDED_HOST"]
  end

  private
    def call_with(headers)
      captured = nil
      app = ->(env) { captured = env; [ 200, {}, [] ] }
      env = Rack::MockRequest.env_for("https://app.kindredquill.com/newsletter", headers)
      IslandHost::Rewriter.new(app).call(env)
      captured
    end

    def with_island_auth_secrets(secrets)
      original = Rails.configuration.x.island_auth_secrets
      Rails.configuration.x.island_auth_secrets = secrets
      yield
    ensure
      Rails.configuration.x.island_auth_secrets = original
    end
end
