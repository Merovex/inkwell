namespace :demo do
  desc "Print the demo-site payload schema (JSON Schema Draft 2020-12)"
  task schema: :environment do
    puts Demo::SiteSchema.new.to_json
  end

  desc "Load a demo-site payload (demo:schema shape) through the model layer"
  task :load, [ :path ] => :environment do |_task, args|
    path = args[:path] or abort "Usage: rails \"demo:load[path/to/payload.json]\""
    payload = JSON.parse(File.read(path))

    # Covers live beside the payload by convention (covers/<user.name>/<key>.*);
    # COVERS_DIR overrides, and a missing directory falls back to cover_url downloads.
    covers_dir = ENV["COVERS_DIR"] ||
      File.join(File.dirname(File.expand_path(path)), "covers", payload.dig("user", "name").to_s)
    covers_dir = nil unless File.directory?(covers_dir)

    account = Demo::SiteLoader.load(payload, covers_dir: covers_dir)
    puts "Loaded #{account.name} (slug #{account.slug}, handle #{account.handle || "unclaimed"}): " \
      "#{account.authors.count} authors, #{account.posts.count} posts, #{account.books.count} books, " \
      "#{account.series.count} series, #{account.collections.count} collections."
  end

  desc "Load a demo circle payload (messages, comments, pulse, beats) through the model layer"
  task :circle, [ :path ] => :environment do |_task, args|
    path = args[:path] or abort "Usage: rails \"demo:circle[path/to/circle.json]\""
    circle = Demo::CircleLoader.load(JSON.parse(File.read(path)))
    pulse = circle.pulse
    puts "Loaded circle #{circle.name} (slug #{circle.slug}): #{circle.members.count} members, " \
      "#{circle.messages.count} messages, #{Comment.current_in(circle.records.active).count} comments, " \
      "#{pulse ? "pulse with #{pulse.beats.count} beats" : "no pulse"}."
  end
end
