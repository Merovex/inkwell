require "test_helper"

# The fast 403 in front of the router: scanner probes never reach Rails routing,
# and nothing legitimate gets caught in the net.
class ScannerBlockerTest < ActiveSupport::TestCase
  test "403s path probes" do
    %w[
      /wp-includes/wlwmanifest.xml
      /wp-login.php
      /xmlrpc.php
      /phpmyadmin/index.php
      /.env
      /.git/config
    ].each do |path|
      status, _headers, _body = call(path)
      assert_equal 403, status, "expected #{path} to be refused"
    end
  end

  test "403s WordPress's permalink-less REST probe, whose path is only a slash" do
    status, _headers, _body = call("/?rest_route=/batch/v1")
    assert_equal 403, status

    # The probe arrives as a POST in the wild (batch/v1 takes a body).
    status, _headers, _body = call("/?rest_route=/batch/v1", method: "POST")
    assert_equal 403, status
  end

  test "lets real requests through" do
    [ "/", "/newsletter", "/.well-known/change-password", "/books?page=2" ].each do |path|
      status, _headers, _body = call(path)
      assert_equal 200, status, "expected #{path} to be served"
    end
  end

  private
    def call(path, method: "GET")
      app = ->(env) { [ 200, {}, [] ] }
      env = Rack::MockRequest.env_for("https://app.kindredquill.com#{path}", method: method)
      ScannerBlocker.new(app).call env
    end
end
