---
type: concept
title: Domain vocabulary
status: active
tags: [naming, data-model, glossary]
created: 2026-07-01
updated: 2026-07-01
sources: [decisions/0002-domain-vocabulary-person-user-account.md]
---

# Domain vocabulary

Canonical names for Inkwell's core concepts. Decided in
[[0002-domain-vocabulary-person-user-account]]. Use **these** words in code,
docs, and UI — not the older `Identity` / `Membership` / `Group` / `bucket`.

## The three core models

- **`Person`** — the global, email-based login. *Who you are across everything.*
  Owns credentials (magic links, passkeys, tokens). One email = one Person.
  *(Fizzy calls this `Identity`.)*
- **`User`** — a Person's membership in one Account: their name, role, and access
  there. One Person can have many Users (one per Account they belong to).
- **`Account`** — the tenant: a writer community's shared space. Owns its content.
  *(Older docs call this `Group` or `bucket`.)*

```
Person ──< User >── Account
(login)   (membership)  (tenant)
```

## Knock-on naming

- Content is scoped to an **Account** — the `Recording` column is `account_id`
  (was `bucket_id` / "group"); models `belongs_to :account`.
- Retired terms: **`Identity`, `Membership`, `Group`, `bucket`.**

## Translation table (when reading source/research)

| Inkwell | Fizzy source | Old notional docs |
|--------|--------------|-------------------|
| `Person` | `Identity` | `Person` |
| `User` | `User` | `Membership` |
| `Account` | `Account` | `Group` / `bucket` |
