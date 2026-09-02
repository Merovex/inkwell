# Recovery for a broadcast whose fan-out job crashed mid-send: the Broadcast
# row's unique record_id blocks a second send, so the post sits on "Emailing
# this post to your subscribers…" forever, with the failed execution parked in
# Solid Queue. Clearing both puts the post back to its pre-send state so the
# Email button works again. Run on a server via
# `bin/kamal app exec "bin/rails broadcast:reset RECORD_ID=36"`.
namespace :broadcast do
  desc "Clear a stuck (unsent) broadcast and its failed job so the post can be emailed again. RECORD_ID=36"
  task reset: :environment do
    record_id = ENV["RECORD_ID"].to_s.strip
    abort "Pass the post's record id: RECORD_ID=36" if record_id.empty?

    record = Record.find_by(id: record_id) or abort "No record ##{record_id}."
    broadcast = record.broadcast or abort "Record ##{record_id} (#{record.to_slug}) has no broadcast — nothing to clear."
    abort "Broadcast ##{broadcast.id} already finished (sent #{broadcast.sent_at}) — refusing to reset a completed send." if broadcast.sent?

    # A partial fan-out means some subscribers already got the email; wiping the
    # delivery ledger and re-sending would double-mail them. Bail so the operator
    # decides — re-enqueueing PostBroadcastJob resumes idempotently instead.
    sent = broadcast.deliveries.where.not(sent_at: nil).count
    if sent.positive?
      abort "#{sent} of #{broadcast.deliveries.count} deliveries were already sent. " \
            "Resetting would re-mail them. To resume where it stopped instead, run: " \
            "PostBroadcastJob.perform_later(Broadcast.find(#{broadcast.id}))"
    end

    # Drop the failed execution (and its job row) so it can't be retried against
    # a broadcast that no longer exists. A still-scheduled job needs no cleanup:
    # once the row is gone it discards itself on DeserializationError. The
    # table_exists? guard covers dev/test, where Solid Queue's tables (production
    # queue database only) aren't around.
    gid = broadcast.to_global_id.to_s
    discarded = if SolidQueue::FailedExecution.table_exists?
      SolidQueue::FailedExecution.joins(:job)
        .where(solid_queue_jobs: { class_name: "PostBroadcastJob" })
        .select { |execution| execution.job.arguments["arguments"].to_a.any? { |arg| arg.is_a?(Hash) && arg["_aj_globalid"] == gid } }
        .each(&:discard).size
    else
      0
    end

    broadcast.destroy!

    puts "Cleared broadcast ##{broadcast.id} for record ##{record.id} (#{record.to_slug})."
    puts "Discarded #{discarded} failed job(s). The post can be emailed again from the dashboard."
  end
end
