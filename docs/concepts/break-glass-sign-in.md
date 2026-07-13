---
type: concept
title: Break-glass sign-in (email-failure escape hatch)
status: active
tags: [auth, ops, kamal, runbook]
created: 2026-07-13
updated: 2026-07-13
sources: []
---

# Break-glass sign-in (email-failure escape hatch)

## Summary
Inkwell's sign-in is passwordless: you request a magic-link **code**, it's
emailed to you, and you redeem it. If email delivery is broken (SES down,
misconfigured, bounced), the domain admin can be locked out with no password
fallback. The **break-glass** command mints a fresh sign-in code for the root
user directly on the server and prints it to the console, so you can sign in
without email. Because only the SHA-256 **digest** of a code is stored, an
existing code's plaintext can't be recovered — the escape hatch generates a
brand-new one.

## How to use it

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
- `bin/kamal rescue-code` is an alias in [`../config/deploy.yml`](../../config/deploy.yml)
  that runs `bin/rails auth:rescue_code` inside the running web container
  (`app exec --reuse`).
- The task [`../../lib/tasks/auth.rake`](../../lib/tasks/auth.rake) picks the
  root user — `User.domain_admin` (the first user, granted domain-admin via the
  [Setup flow](../../app/controllers/setups_controller.rb)), falling back to the
  lowest-id user — then calls `user.sign_in_codes.create!`. The plaintext is
  available on the returned record for the life of that object and never again
  (see [`../../app/models/sign_in_code.rb`](../../app/models/sign_in_code.rb)).
- The verify URL is built with the same host the mailer uses
  (`config.action_mailer.default_url_options`, sourced from the `ses.host`
  credential), so it points at the real site, not localhost.
- Redemption goes through the normal path: `SignInCode.redeem` (consumes the
  matching active code) via `sessions#verify` — the break-glass code is an
  ordinary magic-link code, not a special credential.

See [[domain-vocabulary]] for Person / User / Account naming, and
[`../fizzy-authentication.md`](../fizzy-authentication.md) for the passwordless
protocol Inkwell's auth is modeled on.

## Gotchas / open questions
- **Requires shell access to the server.** This is a last resort for whoever
  holds the deploy keys; there's no in-app trigger by design.
- **Root user only.** It always targets the domain admin, not an arbitrary
  account. To rescue a different user, sign in as root and act from the admin
  backend, or use `bin/kamal console`.
- If **no users exist yet**, the task aborts and points at `/setup` (first-run
  install creates the owner) — there's nothing to rescue.
- The printed code is a live credential for 15 minutes; don't paste it into
  shared logs or tickets.
