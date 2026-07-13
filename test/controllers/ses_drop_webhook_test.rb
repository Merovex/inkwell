require "test_helper"

# SES events tagged with a drop route to the matching DropDelivery (the drip
# side of Webhooks::SesController, alongside broadcasts).
class SesDropWebhookTest < ActionDispatch::IntegrationTest
  setup do
    creator = users(:admin)
    drip = Drip.new(title: "Welcome", active: true, creator:)
    Record.originate(drip)
    @drop = Drop.new(subject: "Hi", delay_days: 0, creator:)
    @drop.body = "x"
    Record.originate(@drop, parent: drip.record)

    @sub = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    stream = drip.enroll(@sub)
    @delivery = DropDelivery.create!(stream:, drop_record: @drop.record, subscriber: @sub,
      status: :sent, sent_at: Time.current)
  end

  teardown { Webhooks::SesController.message_verifier = nil }

  test "an open event stamps the drop delivery and marks the subscriber engaged" do
    post_drop_event("Open")

    assert_response :ok
    assert @delivery.reload.opened_at
    assert @sub.reload.last_engaged_at
  end

  test "a complaint on a drop unsubscribes the subscriber" do
    post_drop_event("Complaint")

    assert @delivery.reload.complained_at
    assert @sub.reload.unsubscribed?
  end

  private
    def post_drop_event(event_type)
      event = {
        "eventType" => event_type,
        "mail" => { "messageId" => "abc", "tags" => {
          "drop_record_id" => [ @drop.record_id.to_s ],
          "subscriber_id" => [ @sub.id.to_s ]
        } }
      }
      Webhooks::SesController.message_verifier = verifier
      post "/webhooks/ses", params: { "Type" => "Notification", "Message" => event.to_json }.to_json,
        headers: { "CONTENT_TYPE" => "text/plain" }
    end

    def verifier
      fake = Object.new
      fake.define_singleton_method(:authentic?) { |_body| true }
      fake
    end
end
