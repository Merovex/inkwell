namespace :site do
  desc "Queue a static-site rebuild — site:rebuild[SLUG], or every account when no slug given"
  task :rebuild, [ :slug ] => :environment do |_t, args|
    accounts = args[:slug].presence ? [ Account.find_by!(slug: args[:slug].upcase) ] : Account.all
    accounts.each do |account|
      SiteBuildJob.schedule(account)
      puts "queued #{account.slug} (builds in ~30s)"
    end
  end

  desc "Latest static-site build job and each account's build status"
  task status: :environment do
    if SolidQueue::Job.table_exists? # dev runs without the queue database
      job = SolidQueue::Job.where(class_name: "SiteBuildJob").order(:id).last
      if job
        state = job.finished_at ? "finished #{job.finished_at}" : "pending (scheduled #{job.scheduled_at})"
        puts "Last SiteBuildJob ##{job.id}: #{state}"
      else
        # Finished jobs are pruned on a schedule, so "none" can also mean
        # "nothing recent" — the per-account stamps below are the durable record.
        puts "No SiteBuildJob in the queue history."
      end

      failed = SolidQueue::FailedExecution.joins(:job)
        .where(solid_queue_jobs: { class_name: "SiteBuildJob" }).order(:id).last
      puts "LAST FAILURE: #{failed.error&.dig('message')}" if failed
    end

    Account.order(:slug).each do |account|
      puts [ account.slug.ljust(8), (account.site_build_status || "—").ljust(8),
        "built #{account.site_built_at&.strftime('%Y-%m-%d %H:%M:%S %Z') || 'never'}" ].join("  ")
    end
  end
end
