# Keeps the edge handle alias in step with the account: the Worker resolves
# sites.kindredquill.com/<handle> through the HOSTNAMES KV key
# "handle:<name>" → slug (handles have no dots, hostnames always do, so the
# key spaces can't collide). Delete the old alias, write the new; enqueued by
# Account whenever the handle changes (the same change also reschedules a
# site build, since baseURL embeds the handle path).
class HandleRouteJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  # Test seam, same as the status polls: a fake Cloudflare client, or nil for
  # the real one.
  cattr_accessor :client_override

  def perform(account, previous_handle)
    client = self.class.client_override || Cloudflare::Client.new
    client.kv_delete("handle:#{previous_handle}") if previous_handle.present?
    client.kv_put("handle:#{account.handle}", account.slug) if account.handle.present?
  end
end
