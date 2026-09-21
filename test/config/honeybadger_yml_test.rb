require "test_helper"
require "erb"

# config/honeybadger.yml decides whether a boot is reportable before any of
# our own initializers run (Honeybadger.init! happens in a Rails
# before_initialize hook), so the "container or not" check has to live in the
# YAML template itself rather than in application code. Fault 134436611: a
# bare local shell in RAILS_ENV=production was reporting itself as a real
# production incident.
class HoneybadgerYmlTest < ActiveSupport::TestCase
  REPORT_DATA_SNIPPET = <<~ERB.strip
    <% if Rails.env.production? %>
    report_data: <%= File.exist?(ENV.fetch("HONEYBADGER_CONTAINER_MARKER", "/.dockerenv")) %>
    <% end %>
  ERB

  test "the checked-in config still contains the snippet under test" do
    assert_includes Rails.root.join("config/honeybadger.yml").read, REPORT_DATA_SNIPPET
  end

  test "production reports only when the container marker exists" do
    assert_equal "true", report_data(rails_env: "production", marker_exists: true)
    assert_equal "false", report_data(rails_env: "production", marker_exists: false)
  end

  test "non-production environments render nothing, leaving the development_environments default" do
    assert_equal "", rendered(rails_env: "test", marker_exists: false).strip
    assert_equal "", rendered(rails_env: "development", marker_exists: false).strip
  end

  private

  # Fakes just the `Rails` constant the snippet touches (env), rather than
  # the whole app: a lexically-scoped constant shadows ::Rails inside this
  # binding without touching the real Rails module mid-suite.
  module FakeScope
    def self.binding_for(rails_env)
      fake_env = ActiveSupport::StringInquirer.new(rails_env)
      remove_const(:Rails) if const_defined?(:Rails, false)
      const_set(:Rails, Struct.new(:env).new(fake_env))
      binding
    end
  end

  def report_data(rails_env:, marker_exists:)
    YAML.safe_load(rendered(rails_env: rails_env, marker_exists: marker_exists))["report_data"].to_s
  end

  def rendered(rails_env:, marker_exists:)
    Dir.mktmpdir do |dir|
      marker_path = File.join(dir, marker_exists ? ".dockerenv" : "absent")
      File.write(marker_path, "") if marker_exists

      original = ENV["HONEYBADGER_CONTAINER_MARKER"]
      ENV["HONEYBADGER_CONTAINER_MARKER"] = marker_path
      begin
        ERB.new(REPORT_DATA_SNIPPET).result(FakeScope.binding_for(rails_env))
      ensure
        ENV["HONEYBADGER_CONTAINER_MARKER"] = original
      end
    end
  end
end
