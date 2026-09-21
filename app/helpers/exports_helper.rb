# How an Export row reads on the Export tab. Color never stands alone: the
# badge always carries the status in words.
module ExportsHelper
  def export_status_label(export)
    return "Expired" if export.built? && !export.downloadable?

    { "pending" => "Building…", "built" => "Ready", "failed" => "Failed" }.fetch(export.status)
  end

  def export_status_variant(export)
    return "accent" if export.downloadable?

    "warning" if export.failed?
  end

  def export_status_detail(export)
    if export.downloadable?
      "#{number_to_human_size(export.archive.byte_size)} · available until #{export.expires_at.to_date.to_fs(:long)}" \
        "#{" · downloaded #{pluralize(export.downloads_count, "time")}" if export.downloads_count.positive?}"
    elsif export.pending?
      "We'll email #{export.creator.email_address} when it's ready."
    elsif export.failed?
      "Something went wrong and we've been notified. You can try again."
    end
  end
end
