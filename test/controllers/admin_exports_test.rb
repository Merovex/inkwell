require "test_helper"

class AdminExportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "the tab is the owner's alone: a member and even root staff get a 404" do
    [ users(:bob), users(:admin) ].each do |user|
      sign_in_as user

      get admin_exports_path
      assert_response :not_found

      assert_no_difference -> { Export.count } do
        post admin_exports_path
      end
      assert_response :not_found
    end
  end

  test "root staff don't see an Export tab on the other settings pages; the owner does" do
    sign_in_as users(:admin)
    get admin_integration_path
    assert_select "a.segmented__seg", text: "Export", count: 0

    sign_in_as users(:alice)
    get admin_integration_path
    assert_select "a.segmented__seg[href=?]", admin_exports_path, text: "Export"
  end

  test "the owner requests an export and sees it building" do
    sign_in_as users(:alice)

    assert_enqueued_with(job: ExportJob) do
      post admin_exports_path
    end
    assert_redirected_to admin_exports_path

    follow_redirect!
    assert_response :success
    assert_select ".list__item .badge", text: "Building…"
    assert_select "form[action=?]", admin_export_download_path(Export.last), count: 0
  end

  test "a second request while one is building is turned away" do
    sign_in_as users(:alice)
    post admin_exports_path

    assert_no_difference -> { Export.count } do
      post admin_exports_path
    end
    assert_equal "An export is already being built. We'll email you when it's ready.", flash[:alert]
  end

  test "downloading a built export counts the fetch and streams the zip — no storage URL to leak" do
    sign_in_as users(:alice)
    export = built_export

    get admin_exports_path
    assert_select ".list__item .badge", text: "Ready"
    assert_select "form[action=?]", admin_export_download_path(export)

    post admin_export_download_path(export)

    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_match(/attachment; filename=".*-export-.*\.zip"/, response.headers["Content-Disposition"])
    assert_equal export.archive.blob.byte_size, response.body.bytesize
    assert_equal 1, export.reload.downloads_count
  end

  test "an expired export can't be downloaded" do
    sign_in_as users(:alice)
    export = built_export

    travel Export::RETENTION + 1.minute do
      sign_in_as users(:alice)
      post admin_export_download_path(export)
    end

    assert_redirected_to admin_exports_path
    assert_equal 0, export.reload.downloads_count
  end

  test "nobody else can download: root staff get a 404 for a built export" do
    export = built_export
    sign_in_as users(:admin)

    post admin_export_download_path(export)

    assert_response :not_found
    assert_equal 0, export.reload.downloads_count
  end

  private
    def built_export
      Export.request(accounts(:merovex), by: users(:alice)).tap(&:build!)
    end
end
