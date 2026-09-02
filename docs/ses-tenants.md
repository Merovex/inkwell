# SES Tenants — context block

Paste as context. Written 2026-08-05. Verify API signatures against
current AWS docs before implementing; the feature is recent.

## What it is

Amazon SES added tenant isolation in August 2025. A **tenant** is a
logical container inside one SES account holding its own email
identities, configuration sets, and templates.

- You pass a tenant name when sending.
- SES tracks sent volume, bounce rate, and complaint rate **per tenant**,
  in real time.
- If a tenant's reputation degrades, SES pauses **that tenant only**.
  Other streams keep sending.
- Reputation policy per tenant: `Standard` (pause on high-impact
  findings), `Strict` (pause on any finding), `None` (metrics only, you
  decide).
- Status changes and new findings publish to EventBridge.
- Limit is 10,000 tenants per account, raisable to 300,000 on request.
- Tenant-level suppression lists exist as of ~July 2026: a bounce for one
  tenant no longer blocks every other tenant from mailing that recipient.
- **Resources can be associated with more than one tenant.** The same
  sending identity can back many tenants while reputation is tracked
  separately for each.

## Why it matters here

Before this feature, SES enforcement was account-level: 5% bounce put the
whole account under review, 10% could pause all sending. On a
multi-tenant platform that meant one author's bad list could lock every
user out of a product whose login is an email link.

Tenants move detection and pausing down to the stream. Account-level
authority still exists above tenants — this reduces blast radius, it does
not remove AWS's ability to act on the account.

**Key consequence:** per-tenant reputation isolation no longer requires
per-tenant sending domains. An author on the shared platform identity can
still have their own isolated reputation and their own auto-pause.

## Proposed tenant structure for Kindred Quill

| Tenant | Identity | Policy | Carries |
|---|---|---|---|
| `platform-auth` | `verify.kindredquill.com` | Strict | Magic links, account confirmation |
| `platform-circles` | `notify.kindredquill.com` | Standard | At-mentions, digests, Pulse |
| `site-<slug>` | `kindredquill.email` (shared) | Standard | Subscriber confirmations, onboarding drips, broadcasts |

One tenant per paying Site, all sharing the customer-lane identity —
`kindredquill.email` per [[email-tenant-byod-plan]] (2026-08-06; this table
originally said `news.kindredquill.com`, which is now KQ's own marketing
identity only, and `site-<account_id>`, before the derived-from-slug
decision). Authors with their own sending domain get that domain associated
with their existing tenant — the tenant boundary doesn't change, only the
identity does.

Strict on auth is deliberate. Auth should pause loudly and early rather
than quietly degrade, and its bounce rate should be near zero anyway.

## What changes in the app

1. ~~`SendingTenant` (or a column on Account)~~ → shipped as
   `accounts.ses_tenant_provisioned_at`; the name is derived
   (`Account#ses_tenant_name`, `site-<slug>`).
2. Tenant provisioning on broadcast-email purchase (not Site creation):
   `EmailConnection.provision_tenant` creates the tenant and associates the
   shared identity + both config sets. Reputation policy set in console
   (not in aws-sdk-sesv2 1.105).
3. Every send passes the tenant name — shipped 2026-08-06: platform mailers
   stamp the two platform tenants in their defaults; site mail merges
   `site_tenant_options` once provisioned.
4. EventBridge → webhook → existing DeliveryEvent pipeline, so tenant
   pause and reputation findings land as events alongside bounces.
5. Author-visible state for "your sending is paused," since SES will now
   pause them without asking you.

## What SES does not solve

- **Consent.** Verification proves a mailbox exists. It says nothing
  about whether the person agreed to hear from this author. Import still
  needs re-confirmation.
- **The product side of a pause.** SES stops the sending. What the author
  sees, what they must do to recover, and who reviews it is yours to
  build.
- **Vendor-level failure.** Regional outage or account-wide action still
  takes everything. If auth uptime matters that much, a dormant
  second-provider identity is the hedge, not a second tenant.
