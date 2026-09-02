require "test_helper"

class HandleRouteJobTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :put, :deleted

    def initialize = (@put, @deleted = {}, [])
    def kv_put(key, value) = @put[key] = value
    def kv_delete(key) = @deleted << key
  end

  teardown { HandleRouteJob.client_override = nil }

  test "writes the new alias and deletes the old one" do
    fake = HandleRouteJob.client_override = FakeClient.new
    account = accounts(:merovex)
    account.update_columns(handle: "merovex") # no callbacks — the job is under test

    HandleRouteJob.perform_now(account, "old-name")

    assert_equal account.slug, fake.put["handle:merovex"]
    assert_includes fake.deleted, "handle:old-name"
  end

  test "a cleared handle only deletes" do
    fake = HandleRouteJob.client_override = FakeClient.new

    HandleRouteJob.perform_now(accounts(:merovex), "merovex")

    assert_empty fake.put
    assert_equal [ "handle:merovex" ], fake.deleted
  end
end
