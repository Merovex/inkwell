require "test_helper"

# The client-IP headers nothing in our stack sets: a scanner that sends them
# either 500s the request (RemoteIp's spoof check) or, via Forwarded, hands
# itself whatever remote_ip it likes.
class ClientIpScrubberTest < ActiveSupport::TestCase
  test "drops a client-supplied Client-IP" do
    env = call_with("HTTP_CLIENT_IP" => "127.0.0.1")
    assert_nil env["HTTP_CLIENT_IP"]
  end

  test "drops a client-supplied Forwarded" do
    env = call_with("HTTP_FORWARDED" => "for=127.0.0.1")
    assert_nil env["HTTP_FORWARDED"]
  end

  test "leaves the proxies' X-Forwarded-For alone" do
    env = call_with("HTTP_X_FORWARDED_FOR" => "195.178.110.104, 172.18.0.2")
    assert_equal "195.178.110.104, 172.18.0.2", env["HTTP_X_FORWARDED_FOR"]
  end

  test "RemoteIp resolves the visitor instead of raising on the scanner's probe" do
    # The live report: a WordPress probe sent "Client-IP: 127.0.0.1" while our
    # proxies had already filled in X-Forwarded-For.
    headers = { "HTTP_CLIENT_IP" => "127.0.0.1", "HTTP_X_FORWARDED_FOR" => "195.178.110.104, 172.18.0.2" }

    assert_raises ActionDispatch::RemoteIp::IpSpoofAttackError do
      remote_ip_for Rack::MockRequest.env_for("https://app.kindredquill.com/", headers)
    end

    assert_equal "195.178.110.104", remote_ip_for(call_with(headers))
  end

  private
    def call_with(headers)
      captured = nil
      app = ->(env) { captured = env; [ 200, {}, [] ] }
      env = Rack::MockRequest.env_for("https://app.kindredquill.com/?rest_route=/batch/v1", headers)
      ClientIpScrubber.new(app).call(env)
      captured
    end

    def remote_ip_for(env)
      captured = nil
      app = ->(inner) { captured = ActionDispatch::Request.new(inner).remote_ip; [ 200, {}, [] ] }
      ActionDispatch::RemoteIp.new(app).call(env)
      captured
    end
end
