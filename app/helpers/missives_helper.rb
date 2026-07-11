module MissivesHelper
  # A mailto: link that opens the admin's mail client as a pre-composed *reply*
  # to a contact submission: To = their address, Subject = "Re: <subject>", and
  # the body quoted like an email reply. The mail sends from the admin's own
  # client, never through this app.
  def missive_reply_mailto(missive)
    quoted = missive.body.each_line.map { |line| "> #{line.chomp}" }.join("\n")
    body = "On #{missive.created_at.strftime('%b %-d, %Y')}, #{missive.name} wrote:\n\n#{quoted}\n\n"
    query = { subject: "Re: #{missive.subject}", body: body }
      .map { |k, v| "#{k}=#{ERB::Util.url_encode(v)}" }.join("&")
    "mailto:#{missive.email_address}?#{query}"
  end
end
