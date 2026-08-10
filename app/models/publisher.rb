# The pipeline's third stage (docs/hugo-build-pipeline.md §5.4): sync a
# rendered build to R2 and flip the site live. Uploads to the immutable
# per-build prefix, writes `pointer.json` LAST — the atomic "build complete"
# marker the edge Worker reads (edge/src/index.js#buildIdFor) — then reaps
# all but the newest KEEP_BUILDS. A failed upload can never take a site
# down: the pointer still names the previous build.
#
# R2 speaks S3 (aws-sdk-s3 via the endpoint below); credentials are the
# bucket-scoped r2.* token pair, account id from config.x.cloudflare.
class Publisher
  BUCKET = "kindredquill-sites"
  KEEP_BUILDS = 3
  # Everything under builds/<id>/ is immutable — cache hard, except HTML,
  # which the Worker serves at whatever path the reader is on: short max-age
  # keeps publishes appearing promptly without purge machinery (§2.4).
  HTML_CACHE  = "public, max-age=60"
  ASSET_CACHE = "public, max-age=31536000, immutable"

  # channel picks where the build lands: :production serves the real site
  # (custom domain + platform path), :preview serves the staging host
  # (preview.kindredquill.com). Each channel has its own build tree and
  # pointer, so a preview never touches what's live.
  def initialize(account, channel: :production)
    @account = account
    @channel = channel
  end

  # Uploads `output` (a rendered public/ tree) as a new build; returns the
  # build id once the pointer names it.
  def publish!(output)
    build_id = Time.current.utc.strftime("%Y%m%d%H%M%S%L")
    prefix = "#{root}builds/#{build_id}/"

    Pathname(output).glob("**/*").select(&:file?).each do |file|
      key = prefix + file.relative_path_from(output).to_s
      type = Marcel::MimeType.for(name: file.basename.to_s, declared_type: "application/octet-stream")
      client.put_object(
        bucket: BUCKET, key: key, body: file.open,
        content_type: type,
        cache_control: type == "text/html" ? HTML_CACHE : ASSET_CACHE
      )
    end

    client.put_object(
      bucket: BUCKET, key: "#{root}pointer.json",
      body: JSON.generate(build_id: build_id),
      content_type: "application/json", cache_control: "no-store"
    )

    reap(build_id)
    build_id
  end

  private
    attr_reader :account, :channel

    # The channel's home in the bucket: production at sites/<slug>/, preview
    # (the staging host) one level deeper at sites/<slug>/preview/.
    def root
      channel == :preview ? "sites/#{account.slug}/preview/" : "sites/#{account.slug}/"
    end

    # Keep the newest KEEP_BUILDS (which includes the one just published);
    # delete the rest so the bucket stays a working set, not an archive.
    def reap(current_build_id)
      prefix = "#{root}builds/"
      builds = client.list_objects_v2(bucket: BUCKET, prefix: prefix, delimiter: "/")
                     .common_prefixes.map { |p| p.prefix.delete_prefix(prefix).delete_suffix("/") }
                     .sort.reverse
      (builds - [ current_build_id ]).drop(KEEP_BUILDS - 1).each do |stale|
        keys = client.list_objects_v2(bucket: BUCKET, prefix: "#{prefix}#{stale}/")
                     .contents.map { |o| { key: o.key } }
        keys.each_slice(1000) { |slice| client.delete_objects(bucket: BUCKET, delete: { objects: slice }) }
      end
    end

    def client
      @client ||= Aws::S3::Client.new(
        endpoint: "https://#{Rails.configuration.x.cloudflare.account_id}.r2.cloudflarestorage.com",
        region: "auto",
        credentials: Aws::Credentials.new(
          # Either spelling: R2's console says "Access Key ID"; the first
          # credentials entry landed as secret_key_id.
          Rails.application.credentials.dig(:r2, :access_key_id) ||
            Rails.application.credentials.dig(:r2, :secret_key_id),
          Rails.application.credentials.dig(:r2, :secret_access_key)
        )
      )
    end
end
