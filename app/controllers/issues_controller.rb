# The newsletter archive page — one broadcast's issue in the browser, exactly
# as it was emailed (the frozen copy from Broadcast#issue!, tip-in included).
# It's the permanent link promo partners check, so it never changes after the
# send: later edits to the post don't reach it. It's live from the moment the
# send is scheduled (partners often want the link before the issue goes out),
# showing the issue as it stands until the send freezes it. A Worker-proxied island on the
# tenant site, noindexed (the minimal layout's meta plus the header) so search
# engines keep to the public post; the lookup is account-scoped so one site's
# link never resolves on another's domain.
class IssuesController < PublicController
  include IslandProtected

  layout "public_minimal"

  def show
    @broadcast = Broadcast.joins(:record)
      .merge(Current.account.records.active).find(params[:id])

    # The slug tail anchors the lookup, so a mangled title still resolves —
    # send it on to the canonical spelling.
    return redirect_to issue_path(@broadcast), status: :moved_permanently unless params[:id] == @broadcast.to_param

    response.set_header("X-Robots-Tag", "noindex")
  end
end
