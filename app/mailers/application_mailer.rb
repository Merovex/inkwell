class ApplicationMailer < ActionMailer::Base
  # User-transactional mail signs d=auth.merovex.press — the root domain never
  # sends (docs/email-architecture.md; supersedes ADR 0015's root-transactional
  # posture). support@ stays inbound-only. The address follows the ses
  # credential so the eventual verify.* identity is a credential change.
  default from: email_address_with_name(
    Rails.application.credentials.dig(:ses, :transactional_from).presence || "noreply@verify.kindredquill.com",
    "Inkwell"
  )
  layout "mailer"

  # Mailers don't include app helpers by default, but the Action Text blob
  # partial (active_storage/blobs/_blob) is shared with the web and calls
  # ApplicationHelper#attachment_variation — needed whenever a broadcast post
  # embeds an image.
  helper :application

  private
    # URL options for links that live on the APP host — sign-in, circles,
    # settings. Once host-role enforcement is on, those routes exist only
    # there; the default mailer host (a tenant domain) would 404 them
    # (ADR 0018). Empty when unenforced — links fall back to the default host,
    # the legacy single-tenant behavior.
    def app_url_options
      AccountHost.enforced? ? { host: AccountHost.app_host } : {}
    end

    # URL options for links that live on the account's PUBLIC site — the post's
    # web page, newsletter confirm/keep/unsubscribe, contact confirm. The reader
    # belongs to the press, so links must land on the press's own address. Every
    # subscriber-facing link passes through here; a bare *_url helper would emit
    # the app host instead. Shared with the admin's share-link banner via
    # AccountHost.public_url_options.
    def public_url_options(account)
      AccountHost.public_url_options(account)
    end

    # Site broadcast mail speaks with the site's own voice: Account#broadcast_from
    # resolves the live BYOD sending domain, else <handle>@ the shared lane
    # (docs/email-tenant-byod-plan.md — supersedes the hardcoded personal name
    # the old marketing_from carried). The account's contact address becomes
    # Reply-To on the caller so replies still reach the site. NB the warm-standby
    # Postmark pipe has not verified these Froms — a provider flip must
    # re-verify there first.
    def broadcast_from(account) = account.broadcast_from

    # Once the site's SES tenant exists, its sends declare it so reputation
    # accrues there — merged into each mailer's delivery_method_options
    # (association is passive; only the stamp attributes the send).
    def site_tenant_options(account)
      account.ses_tenant_provisioned? ? { tenant_name: account.ses_tenant_name } : {}
    end

    # Bulk newsletter mail (post broadcasts, drip steps) must ride Postmark's
    # Broadcast stream, not the default transactional one — Postmark rejects bulk
    # sends on a transactional stream. Confirmation/sign-in mail sets no stream and
    # so stays on the default `outbound`. Overridable via credentials if the stream
    # is ever renamed.
    def broadcast_stream
      Rails.application.credentials.dig(:postmark, :broadcast_stream).presence || "broadcast"
    end

    # Platform bulk mail to Users (notification digests, Pulse asks) — the
    # platform's own voice on its own identity: stream 2 signs
    # notify.kindredquill.com (docs/email-architecture.md), never the
    # verification identity and no longer the Subscriber identity.
    def platform_bulk_from
      address = Rails.application.credentials.dig(:ses, :notify_from).presence || "noreply@notify.kindredquill.com"
      email_address_with_name(address, "Inkwell")
    end
end
