require "test_helper"

# Importing a partner's sign-up CSV from the roster: upload previews without
# touching the list; confirming sends the double opt-in invitations, once.
class AdminSubscriberImportsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  setup { sign_in_as users(:admin) }

  test "uploading previews what would happen and sends nothing" do
    Subscriber.opt_in_confirmed(email_address: "kept@example.com", source: "bookfunnel")

    assert_no_enqueued_emails do
      post admin_subscribers_imports_path, params: { subscriber_import: { source: "storyorigin", file: csv_upload("new@example.com", "kept@example.com") } }
    end

    import = SubscriberImport.last
    assert_redirected_to admin_subscribers_import_path(import)
    follow_redirect!
    assert_select "dt", "New — will get a confirmation email"
    assert_select "dt", "Already subscribed"
    assert_select "button", "Send 1 invitation"
    assert_not Subscriber.exists?(email_address: "new@example.com")
  end

  test "a file without an Email column is sent back with the reason" do
    post admin_subscribers_imports_path, params: { subscriber_import: { source: "storyorigin", file: csv_upload(header: "Name") } }

    assert_response :unprocessable_entity
    assert_select ".error-summary", /no Email column/
  end

  test "confirming sends the invitations, and a second click sends nothing more" do
    post admin_subscribers_imports_path, params: { subscriber_import: { source: "storyorigin", file: csv_upload("new@example.com") } }
    import = SubscriberImport.last

    perform_enqueued_jobs(only: SubscriberImportJob) do
      post admin_subscribers_import_invitation_path(import)
    end
    assert_enqueued_emails 1
    assert import.reload.invited?
    assert Subscriber.find_by!(email_address: "new@example.com").pending?

    assert_no_enqueued_jobs(only: SubscriberImportJob) do
      post admin_subscribers_import_invitation_path(import)
    end
  end

  test "another site's import is out of reach" do
    other_site = Account.create!(name: "Second Press", owner: users(:bob))
    other = SubscriberImport.create!(account: other_site, creator: users(:bob), source: "import", file: csv_upload("x@example.com"))

    get admin_subscribers_import_path(other)
    assert_response :not_found
  end

  private
    def csv_upload(*emails, header: "Email")
      Rack::Test::UploadedFile.new(StringIO.new(CSV.generate { |csv| csv << [ header ]; emails.each { csv << [ it ] } }), "text/csv", original_filename: "export.csv")
    end
end
