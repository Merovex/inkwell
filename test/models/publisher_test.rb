require "test_helper"

# The R2 sync + pointer flip. Stubbed S3 client — the contract under test is
# keys, metadata, pointer-last ordering, and the reaper's arithmetic.
class PublisherTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:merovex)
    @publisher = Publisher.new(@account)
    @client = Aws::S3::Client.new(stub_responses: true, region: "auto")
    @publisher.instance_variable_set(:@client, @client)
    @puts = []
    @client.stub_responses(:put_object, ->(ctx) { @puts << ctx.params; {} })
    @client.stub_responses(:list_objects_v2, { common_prefixes: [], contents: [] })
  end

  test "uploads the tree under an immutable build prefix and flips the pointer last" do
    output = Pathname(Dir.mktmpdir)
    output.join("index.html").write("<html>home</html>")
    output.join("css").mkpath
    output.join("css/site.css").write("body{}")

    build_id = @publisher.publish!(output)

    keys = @puts.map { |p| p[:bucket] == "kindredquill-sites" && p[:key] }
    assert_includes keys, "sites/#{@account.slug}/builds/#{build_id}/index.html"
    assert_includes keys, "sites/#{@account.slug}/builds/#{build_id}/css/site.css"

    # Pointer written LAST — the atomic "build complete" marker.
    assert_equal "sites/#{@account.slug}/pointer.json", @puts.last[:key]
    assert_equal({ "build_id" => build_id }, JSON.parse(@puts.last[:body]))

    html = @puts.find { |p| p[:key].end_with?("index.html") }
    assert_equal "text/html", html[:content_type]
    assert_equal Publisher::HTML_CACHE, html[:cache_control]
    css = @puts.find { |p| p[:key].end_with?("site.css") }
    assert_equal Publisher::ASSET_CACHE, css[:cache_control]
  end
end
