#!/usr/bin/env ruby
# frozen_string_literal: true

# Replays a BookFunnel "Reader Signup" CSV export through the Sendy-compatible
# subscribe endpoint (Sendy::SubscriptionsController) — the backfill twin of the
# live integration, for readers who signed up before it was connected, and the
# recovery path if a push is ever missed.
#
# It talks HTTP, not the database, on purpose: it needs no server access, and it
# walks the exact path BookFunnel will walk, so a successful import is also a
# test of the integration. Every push is idempotent, so re-running a CSV — or
# running two exports that overlap — costs nothing but the requests.
#
# Only rows BookFunnel marks Confirmed AND Consented are sent; anything else is
# reported and skipped, because those two columns are the consent we are relying
# on in place of our own double opt-in.
#
#   ruby script/import_bookfunnel_csv.rb ~/Downloads/export.csv [more.csv ...] \
#     --host https://app.kindredquill.com --key <api key> --list <list id>
#
# Prints what it would do and sends nothing until you add --live. The key and
# list ID are on System settings → Integrations.
#
# Takes any number of exports at once and sends each address only once, keeping
# the first row that carries it — consecutive BookFunnel exports overlap heavily
# (yesterday's readers are in today's file too). The endpoint is idempotent
# regardless, so a duplicate that slips through changes nothing; this just keeps
# the run honest about what it actually did.
#
# NOTE: an imported reader is confirmed on arrival, so they enroll in the live
# drip and the day-0 email goes out within moments. Import when you're ready for
# that to happen.

require "csv"
require "net/http"
require "optparse"
require "uri"

options = { live: false }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby script/import_bookfunnel_csv.rb <csv> --host URL --key KEY --list LIST_ID [--live]"
  opts.on("--host URL", "Sendy Host URL, e.g. https://app.kindredquill.com") { options[:host] = it }
  opts.on("--key KEY", "The site's API key (System settings → Integrations)") { options[:key] = it }
  opts.on("--list ID", "The site's list ID (handle or slug)") { options[:list] = it }
  opts.on("--live", "Actually send. Without this, nothing leaves the machine.") { options[:live] = true }
  opts.on("-h", "--help") { puts opts; exit }
end
parser.parse!

# Whitespace-only arguments are dropped rather than treated as filenames: a
# stray "\" before a line break escapes the space instead of continuing the
# line, and the shell hands us a lone " " that looks like nothing at all.
csv_paths = ARGV.map(&:strip).reject(&:empty?)
missing = [ ("a CSV path" if csv_paths.empty?), ("--host" if options[:host].nil?),
            ("--key" if options[:key].nil?), ("--list" if options[:list].nil?) ].compact
if missing.any?
  abort "Missing #{missing.join(", ")}.\n\n#{parser}"
end
# inspect, not the bare path — an argument you cannot see is the hardest kind
# to debug from an error message.
csv_paths.each { |path| abort "No such file: #{path.inspect}" unless File.exist?(path) }

endpoint = URI.join(options[:host], "/subscribe")
yes = ->(value) { value.to_s.strip.casecmp?("yes") }

# foreach, not read: CSV.read hands back a Table, which flat_map would keep
# whole (one "row" per file, every field an array of that column).
rows = csv_paths.flat_map { |path| CSV.foreach(path, headers: true).to_a }
puts "#{rows.size} row(s) in #{csv_paths.map { |path| File.basename(path) }.join(", ")} → #{endpoint}"
puts options[:live] ? "LIVE — readers will be added and the drip will start." : "Dry run. Add --live to send."
puts

# Parse and filter first, so a dry run reads the files and touches nothing else —
# no connection, no server needed to preview an export.
sendable = []
seen = {}
skipped = duplicates = 0

rows.each do |row|
  email = row["Email"].to_s.strip

  if email.empty?
    puts "  skip  (no email address)"
    skipped += 1
    next
  end

  # Same normalization the server applies, so two spellings of one address
  # count as the duplicate they are.
  key = email.downcase
  if seen.key?(key)
    seen_as = seen[key] == email ? "already in this run" : "already in this run as #{seen[key]}"
    puts "  dup   #{email} — #{seen_as}"
    duplicates += 1
    next
  end
  seen[key] = email

  # The two columns that carry the consent we're standing on.
  unless yes.call(row["Confirmed"]) && yes.call(row["Consented"])
    puts "  skip  #{email} — Confirmed=#{row["Confirmed"].inspect} Consented=#{row["Consented"].inspect}"
    skipped += 1
    next
  end

  sendable << {
    "api_key" => options[:key],
    "list" => options[:list],
    "email" => email,
    "name" => row["First Name"].to_s.strip,
    "ipaddress" => row["IP Address"].to_s.strip,
    "country" => row["Country Code"].to_s.strip,
    "gdpr" => row["GDPR Country"].to_s.strip,
    "boolean" => "true"
  }.reject { |_, value| value.to_s.empty? }
end

unless options[:live]
  sendable.each { |form| puts "  would send  #{form["email"]} (#{form["country"] || "?"}, GDPR=#{form["gdpr"] || "unknown"})" }
  puts
  puts "#{sendable.size} would be sent, #{duplicates} duplicate(s) ignored, #{skipped} skipped. Re-run with --live."
  exit
end

added = failed = 0

Net::HTTP.start(endpoint.host, endpoint.port, use_ssl: endpoint.scheme == "https") do |http|
  sendable.each do |form|
    request = Net::HTTP::Post.new(endpoint)
    request.set_form_data(form)
    body = http.request(request).body.to_s.strip

    if body == "true" || body == "1"
      puts "  added  #{form["email"]}"
      added += 1
    else
      puts "  FAILED #{form["email"]} — #{body}"
      failed += 1
    end

    sleep 0.1
  end
end

puts
puts "#{added} sent, #{duplicates} duplicate(s) ignored, #{skipped} skipped, #{failed} failed."
puts "A reader already on the list answers the same 1 as a new one, so \"sent\" means accepted, not necessarily new." if added.positive?
exit 1 if failed.positive?
