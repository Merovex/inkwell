namespace :site do
  desc "Export an account's published content as the Hugo JSON transport (docs/hugo-build-pipeline.md §4). Usage: rails 'site:export[account_id]'"
  task :export, [ :account_id ] => :environment do |_task, args|
    abort "Usage: rails 'site:export[account_id]'" if args.account_id.blank?

    account = Account.find(args.account_id)
    workspace = Exporter.new(account).export!

    # Bundle the workspace for easy retrieval (scp / forensics); the archive
    # sits beside the workspace as <build_id>.tar.gz.
    archive = "#{workspace}.tar.gz"
    system("tar", "-czf", archive, "-C", workspace.parent.to_s, workspace.basename.to_s, exception: true)

    puts "Exported #{account.slug} to #{workspace}"
    puts "Archive: #{archive}"
  end
end
