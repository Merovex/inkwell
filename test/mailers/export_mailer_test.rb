require "test_helper"

class ExportMailerTest < ActionMailer::TestCase
  test "ready goes to the requester and links to the signed-in Export page, never the file" do
    export = Export.request(accounts(:merovex), by: users(:alice))

    mail = ExportMailer.ready(export)

    assert_equal [ users(:alice).email_address ], mail.to
    assert_equal "Your Merovex Press export is ready", mail.subject
    [ mail.html_part, mail.text_part ].each do |part|
      assert_includes part.body.to_s, "/#{accounts(:merovex).slug}/admin/exports"
      assert_not_includes part.body.to_s, "active_storage"
    end
  end
end
