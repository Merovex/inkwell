---
type: concept
title: Console sign-in — bootstrap & break-glass (email-independent)
status: active
tags: [auth, ops, kamal, runbook]
created: 2026-07-13
updated: 2026-07-13
sources: []
---

# Console sign-in — bootstrap & break-glass (email-independent)

## Summary
Inkwell's sign-in is passwordless: you request a magic-link **code**, it's
emailed to you, and you redeem it. That's a problem in two moments when email
isn't a reliable channel: **first-run bootstrap** (SES may not be configured yet)
and **email outage** (SES down/misconfigured, admin locked out with no password
fallback). Two console rake tasks close both gaps by minting a code and printing
it directly on the server — no email sent:

- **`auth:setup_admin`** — create the first user (domain admin) on a fresh
  install and print a sign-in code.
- **`auth:rescue_code`** — mint a fresh code for the existing root user (the
  break-glass escape hatch).

Because only the SHA-256 **digest** of a code is stored, an existing code's
plaintext can't be recovered — both tasks generate a brand-new code and print it
on creation.

## Bootstrap the first admin (no SES needed)

On a fresh install with no users yet, create the owner and get a code without
sending any email:

```
bin/kamal app exec --reuse "bin/rails auth:setup_admin EMAIL=you@example.com"
```

It creates the domain admin and prints the same code/URL/expiry block as below.
Aborts if any user already exists (use `rescue_code` then) or the email is
invalid.

> **Keep `EMAIL=…` *inside* the quoted command string.** Rake turns
> `KEY=VALUE` arguments into `ENV` entries, so `EMAIL=you@example.com` must be
> part of the command Kamal runs in the container —
> `"bin/rails auth:setup_admin EMAIL=you@example.com"`. If it's placed outside
> the quotes it's appended to `kamal app exec` itself (parsed by Kamal, not the
> rails process) and the task sees no email. This is also why `setup_admin` is
> not a fixed `deploy.yml` alias: the email varies per install.

This is the recommended bootstrap: it depends on nothing but shell access. The
alternative — verifying your address in **SES sandbox** and using the web
`/setup` flow — also works, but couples first login to email being wired up
correctly on day one (see Gotchas).

## Break-glass for an existing admin

On a deployed host:

```
bin/kamal rescue-code
```

It prints the user, the formatted code, a ready-to-click verify URL, and the
expiry:

```
User:  merovex@hey.com (merovex@hey.com)
Code:  FINS-LFFT
URL:   https://merovex.press/session/verify?code=FINSLFFT
Expires in 15 minutes.
```

Redeem it either way:
- open the **URL** in a browser, or
- go to the sign-in page and type the **Code** into the manual-entry form
  (dashes/spaces/casing are forgiven).

The code is single-use and expires in **15 minutes** (`SignInCode::EXPIRES_IN`);
run the command again for a fresh one if it lapses.

Run it directly (outside Kamal) with:

```
bin/rails auth:rescue_code
```

## How it works
- Both tasks live in [`../../lib/tasks/auth.rake`](../../lib/tasks/auth.rake)
  and share a `print_sign_in_code` helper that calls
  `user.sign_in_codes.create!` and prints code + URL + expiry. The plaintext is
  available on the returned record for the life of that object and never again
  (see [`../../app/models/sign_in_code.rb`](../../app/models/sign_in_code.rb)).
- `auth:setup_admin` mirrors the web [Setup flow](../../app/models/setup.rb):
  it creates `User.new(role: :domain_admin)` — but **prints a code instead of
  emailing** a sign-up link. Guarded by `User.exists?` so it only runs on a
  fresh install.
- `auth:rescue_code` picks the root user — `User.domain_admin` (the first user),
  falling back to the lowest-id user — and mints a code for them.
- `bin/kamal rescue-code` is an alias in
  [`../../config/deploy.yml`](../../config/deploy.yml) for
  `app exec --reuse "bin/rails auth:rescue_code"`. `setup_admin` takes an
  `EMAIL=` argument so it's run via `app exec` directly rather than a fixed
  alias.
- The verify URL is built with the same host the mailer uses
  (`config.action_mailer.default_url_options`, sourced from the `ses.host`
  credential), so it points at the real site, not localhost.
- Redemption goes through the normal path: `SignInCode.redeem` (consumes the
  matching active code) via `sessions#verify`, which calls
  `start_new_session_for` — these are ordinary magic-link codes, not special
  credentials.

## Effect on existing sessions
Minting a code (`sign_in_codes.create!`) touches **only** the `sign_in_codes`
table — it does **not** log anyone out. Sessions are separate rows
(`user.sessions`); redeeming a code **creates a new** `Session` and sets the
cookie in whichever browser redeemed it
([`authentication.rb`](../../app/controllers/concerns/authentication.rb) —
`start_new_session_for`). It never destroys other sessions, and cookies are
per-browser, so any browser you're already signed into stays signed in. Only
sign-out (`terminate_session`) or deleting the `Session` row ends a session.

See [[domain-vocabulary]] for Person / User / Account naming, and
[`../fizzy-authentication.md`](../fizzy-authentication.md) for the passwordless
protocol Inkwell's auth is modeled on.

## SES sandbox — does it cover first login?
Yes, with a catch. In the SES **sandbox** you can send email, but only **to
verified addresses**, capped at ~200/day and 1 msg/sec. So the web `/setup`
flow's sign-up email *will* arrive **if you first verify your own admin address
as a recipient identity in SES**. What the sandbox blocks is emailing arbitrary
people (subscribers, newsletters) — that needs SES **production access**. For
the very first login, `auth:setup_admin` is more robust than relying on sandbox
email: it has zero email dependency.

## Gotchas / open questions
- **Requires shell access to the server.** These are a last resort / bootstrap
  for whoever holds the deploy keys; there's no in-app trigger by design.
- **Root user only.** `rescue_code` always targets the domain admin, not an
  arbitrary account. To rescue a different user, sign in as root and act from the
  admin backend, or use `bin/kamal console`.
- `setup_admin` aborts if **any** user exists; `rescue_code` aborts if **no**
  user exists and points you at `setup_admin`. They're mutually exclusive by
  design.
- The printed code is a live credential for 15 minutes; don't paste it into
  shared logs or tickets.
