require "test_helper"
require "open3"
require "tmpdir"

# Full-stack proof for fault 134436611: a real production boot outside a
# container (a local shell testing config/initializers/app_host_required.rb,
# for example) must not mark itself reportable to Honeybadger, even though a
# real Kamal deploy's container must. SECRET_KEY_BASE_DUMMY exempts the boot
# from the APP_HOST guard itself so we can observe Honeybadger's decision
# without the process raising first.
class HoneybadgerBootReportingTest < ActiveSupport::TestCase
  test "a production boot without the container marker does not report" do
    assert_equal "false", public_in_subprocess(marker_path: Dir.mktmpdir + "/absent")
  end

  test "a production boot with the container marker present does report" do
    Dir.mktmpdir do |dir|
      marker = File.join(dir, ".dockerenv")
      File.write(marker, "")
      assert_equal "true", public_in_subprocess(marker_path: marker)
    end
  end

  private

  def public_in_subprocess(marker_path:)
    env = {
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE_DUMMY" => "1",
      "HONEYBADGER_CONTAINER_MARKER" => marker_path
    }
    out, err, status = Open3.capture3(env, "bin/rails", "runner",
      "puts Honeybadger.config.public?", chdir: Rails.root.to_s)
    assert status.success?, "subprocess failed: #{err}"
    out.strip
  end
end
