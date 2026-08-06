require "test_helper"

# The initializer prepend (config/initializers/ses_tenant_delivery.rb): the gem
# whitelists three SendEmail keys; tenant_name must join the call, not leak
# into the client constructor (where it raises).
class SesTenantDeliveryTest < ActiveSupport::TestCase
  test "tenant_name rides the SendEmail call" do
    calls = []
    client = Aws::SESV2::Client.new(stub_responses: true, region: "us-east-1")
    client.stub_responses(:send_email, ->(ctx) { calls << ctx.params; { message_id: "m-1" } })

    mailer = Aws::ActionMailer::SESV2::Mailer.new(sesv2_client: client,
      tenant_name: "site-TESTAC", configuration_set_name: "inkwell-marketing")
    mailer.deliver!(Mail.new(from: "noreply@kindredquill.email", to: "reader@example.com",
      subject: "Hi", body: "Hello"))

    assert_equal "site-TESTAC", calls.first[:tenant_name]
    assert_equal "inkwell-marketing", calls.first[:configuration_set_name]
  end

  test "without a tenant_name the params carry none" do
    calls = []
    client = Aws::SESV2::Client.new(stub_responses: true, region: "us-east-1")
    client.stub_responses(:send_email, ->(ctx) { calls << ctx.params; { message_id: "m-1" } })

    Aws::ActionMailer::SESV2::Mailer.new(sesv2_client: client)
      .deliver!(Mail.new(from: "a@example.com", to: "b@example.com", subject: "Hi", body: "Hello"))

    assert_nil calls.first[:tenant_name]
  end
end
