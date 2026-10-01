require "test_helper"

class SubscriberImportTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "invites each new address once, through double opt-in, filed under the source" do
    import = import_of("New@Example.com", "new@example.com", "other@example.com")

    assert_equal %w[ new@example.com other@example.com ], import.emails
    assert_enqueued_emails(2) { import.invite! }

    subscriber = Current.account.subscribers.find_by!(email_address: "new@example.com")
    assert subscriber.pending?
    assert_equal "StoryOrigin", subscriber.source_label
    assert import.invited?
    assert_equal({ "invite" => 2 }, import.tally)
  end

  test "leaves every address the site already holds alone — no re-invite, no re-mail" do
    kept = Subscriber.opt_in_confirmed(email_address: "kept@example.com", source: "bookfunnel")
    gone = Subscriber.opt_in(email_address: "gone@example.com").tap(&:unsubscribe!)
    import = import_of("kept@example.com", "gone@example.com")

    assert_no_enqueued_emails { import.invite! }

    assert gone.reload.unsubscribed?, "an opt-out outranks an old partner export"
    assert_equal "bookfunnel", kept.reload.source
    assert_equal({ "confirmed" => 1, "unsubscribed" => 1 }, import.tally)
  end

  test "skips addresses the suppression list blocks" do
    Suppression.impose!(person: Person.create!(email_address: "bounced@example.com"), reason: :hard_bounce)
    import = import_of("bounced@example.com")

    assert_equal({ "bounced@example.com" => "suppressed" }, import.outcomes)
    assert_no_enqueued_emails { import.invite! }
  end

  test "the preview writes nothing" do
    import = import_of("new@example.com")

    assert_equal({ "invite" => 1 }, import.summary)
    assert_not Current.account.subscribers.exists?(email_address: "new@example.com")
  end

  test "finds the address column under the names partners use" do
    import = import_of("reader@example.com", header: "Email Address")

    assert_equal %w[ reader@example.com ], import.emails
  end

  test "refuses a file with no Email column" do
    import = SubscriberImport.new(source: "storyorigin", file: upload("Name\nReader\n"))

    assert_not import.valid?
    assert_includes import.errors[:file], "has no Email column"
  end

  private
    def import_of(*emails, header: "Email")
      SubscriberImport.create!(creator: users(:admin), source: "storyorigin", file: upload(CSV.generate { |csv| csv << [ "First Name", header ]; emails.each { csv << [ "Reader", it ] } }))
    end

    def upload(csv)
      Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "export.csv")
    end
end
