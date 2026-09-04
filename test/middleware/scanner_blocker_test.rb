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

  # The bug that broke the BookFunnel integration on day one: Sendy's API paths
  # end in .php, so our own routes were refused at the front of the stack —
  # 403 Forbidden, invisible in the logs, and BookFunnel reporting only
  # "We had trouble verifying your settings: Forbidden".
  test "lets the Sendy API paths we actually answer through" do
    %w[
      /api/subscribers/active-subscriber-count.php
      /api/subscribers/subscription-status.php
    ].each do |path|
      status, _headers, _body = call(path, method: "POST")
      assert_equal 200, status, "expected #{path} to reach Rails"
    end
  end

  # A Sendy call we haven't implemented reaches Rails and 404s in the log,
  # rather than disappearing into a 403 nobody can see.
  test "lets an unimplemented Sendy API path through to a visible 404" do
    status, _headers, _body = call("/api/subscribers/delete.php", method: "POST")
    assert_equal 200, status, "the stub app stands in for Rails' 404 here"
  end

  test "still refuses every other .php path, including near misses" do
    %w[
      /api/campaigns/create.php
      /api/subscribers/active-subscriber-count.php/extra
      /wp-content/api/subscribers/subscription-status.php
      /api/subscribers/../../wp-login.php
    ].each do |path|
      status, _headers, _body = call(path, method: "POST")
      assert_equal 403, status, "expected #{path} to be refused"
    end
  end

  private
    def call(path, method: "GET")
      app = ->(env) { [ 200, {}, [] ] }
      env = Rack::MockRequest.env_for("https://app.kindredquill.com#{path}", method: method)
      ScannerBlocker.new(app).call env
    end
end
