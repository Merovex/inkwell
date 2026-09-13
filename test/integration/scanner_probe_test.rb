require "test_helper"

# Full-stack check for issue #32. The unit test proves the middleware says no;
# this proves the refusal happens before Rack::MethodOverride parses the body,
# because parsing *this* body is what 500ed in production: a form part
# declaring charset=utf-16le makes Rack force-encode the field name, and the
# query parser then raises Encoding::CompatibilityError.
class ScannerProbeTest < ActionDispatch::IntegrationTest
  BOUNDARY = "----WebKitFormBoundaryx8jO2oVc6SWP3Sad"
  PROBE_BODY = "--#{BOUNDARY}\r\n" \
    "Content-Disposition: form-data; name=\"0\"\r\n" \
    "Content-Type: text/plain; charset=utf-16le\r\n\r\n" \
    "[\"$@1\",[\"$\"]]\r\n" \
    "--#{BOUNDARY}--\r\n"

  test "the Next.js server-action probe is refused with 403, not 500" do
    [ "/", "/session/new" ].each do |path|
      post path,
        params: PROBE_BODY,
        headers: {
          "CONTENT_TYPE" => "multipart/form-data; boundary=#{BOUNDARY}",
          "HTTP_NEXT_ACTION" => "x",
          "HTTP_ACCEPT" => "text/x-component"
        }
      assert_response :forbidden, "expected the probe to #{path} to be refused"
    end
  end
end
