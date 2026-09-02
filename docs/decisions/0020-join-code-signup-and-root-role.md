---
type: decision
title: Join-code signup, owner_id authority, and the root role
status: accepted
tags: [rails, signup, authorization, roles, multi-tenancy]
created: 2026-07-28
updated: 2026-07-28
sources: [./0017-phase-1-tenancy-model.md, ~/Work/fizzy, ../account-creation-concern.md]
---

# 0020. Join-code signup, owner_id authority, and the root role

## Context
Accounts need self-service birth (Basecamp's two-phase shape: verify the email
first, create the tenant last), gated hard for closed beta. Fizzy's per-account
roles (owner/admin/member/system) exist because its User IS a per-account
membership; Inkwell's users are global, so the same facts land differently.

## Decision

**Signup (phase 1) is gated by a join code** — an inviter-owned, multi-use,
rotatable Crockford code (`JoinCode`, modeled on Fizzy's `Account::JoinCode`;
deliberately NOT named "invitation", a term reserved for future per-person
invites). One live code per inviter; rotation kills the old string for
everyone holding it and touches nobody else. New users record
`users.inviter_id` — the abuse-tracing referral chain. Who may hold a code is
`User#can_invite?`: root always, everyone once the hard-coded open-beta
switch (`config.x.join_codes.open`, default false) flips. The registration
policy config (:invite_only/:open) is retired — the code IS the policy.

**Account creation (phase 2)** is any signed-in user founding a press:
`Account.create_with_owner` (account + owner membership, atomic), press name
unique (DB index, case-insensitive validation), landing straight in
`/{SLUG}/admin`. Reached from the account picker ("Create a press").

**Authority: owner_id, not roles.** The account owner is per-account
superuser by virtue of `accounts.owner_id` (`User#administers?`); transfers
are console-only, never UI. Global `users.role` renamed
`domain_admin` → **`root`** = platform staff: passes every admin gate and the
membership gate (support access to any tenant). Per-account admin/member
roles wait on `account_users` until team features exist (Fizzy's system role
has no Inkwell equivalent).

**Honeypots** (invisible_captcha) on signup AND sign-in create; both fake the
"check your email" page on a trip, persisting and sending nothing.

## Consequences
- Signup-created users stay global-role member forever; `root` is only ever
  granted by hand (or the first-user Setup flow).
- Ops: mint the first code in console — `JoinCode.create!(user: User.root.first)`;
  rotate on abuse with `join_code.rotate!`.
- Open beta = flip one config line + surface "your invite code" in personal
  settings (not yet built).
- Content policies (`ApplicationPolicy#admin?`) now read
  `administers?(Current.account)` — refine when multi-user accounts arrive.
