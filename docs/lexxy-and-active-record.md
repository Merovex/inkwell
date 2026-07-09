# Can Lexxy Be Decoupled From Active Record? — Research Summary

*Research summary for Inkwell. Short version: **Lexxy itself isn't coupled to
Active Record** — Action Text + Active Storage are. Lexxy is a Lexical-based JS
editor that speaks the Action Text protocol. The tenancy pain you remember is an
Action Text/Active Storage limitation, which Lexxy neither fixes nor worsens.*

Related: [`multi-tenancy.md`](./multi-tenancy.md).

---

## Where the Active Record coupling actually lives

Three layers; only the editor is AR-free:

| Layer | AR-coupled? | What it is |
|-------|-------------|-----------|
| **Editor** (Lexxy JS / Lexical web component) | **No** | Edits/emits HTML; talks to two endpoints (upload + prompts). Shipped as `@37signals/lexxy` on npm. |
| **Persistence** (Action Text) | **Yes** | `action_text_rich_texts` table, `has_rich_text`. |
| **Attachments** (Active Storage) | **Yes** | Direct Upload → returns `signed_id` (blob) + `attachable_sgid` (signed GlobalID) embedded in the HTML; server resolves the SGID via `GlobalID::Locator`. |

The editor's only server touchpoints are the **Active Storage Direct Upload
endpoint** and the **prompts/mentions fetch endpoint**. That is the seam where
decoupling or tenanting happens.

---

## Can it be decoupled? Two senses

1. **Editor without Action Text at all** — *possible but fighting conventions
   today.* The web component renders/emits HTML regardless; you could persist
   that HTML yourself and host your own upload + mention endpoints. But
   documented config hooks are thin (`toolbar`, `attachments` on/off,
   `permittedAttachmentTypes`, `attachmentTagName`,
   `attachmentContentTypeNamespace`, `authenticatedUploads`) — **no documented
   custom-endpoint / custom-resolver hook**, and the **standalone JS package is
   on the roadmap but unchecked**. Not a supported non-Rails path yet.
2. **Keep Action Text, make it tenant-safe** — *the pragmatic path, and what
   Fizzy demonstrates.*

---

## The tenancy angle — why it historically hurt

The friction was never Lexxy vs. tenancy; it was **row-level
(`default_scope`) multi-tenancy — or database-per-tenant — vs. Action
Text/Active Storage**, for three concrete reasons:

- Action Text's `action_text_rich_texts` and Active Storage's `blobs`/
  `attachments` tables **have no tenant column**, and they're framework-owned
  models you can't easily augment with a tenant scope.
- Active Storage's `DirectUploads`/`Blobs` controllers and the Action Text
  controller are **Rails-internal** — they don't run through your
  tenant-resolution middleware, so uploads/resolves can land outside tenant
  context (acute in database-per-tenant setups).
- **SGID resolution bypasses default scopes** — `GlobalID::Locator.locate_signed`
  does a bare `find`, so a tenant `default_scope` either doesn't constrain it or
  makes it raise. This is the classic reason gem-based row-level tenancy
  "couldn't support" Action Text attachments.

---

## The key proof point: Fizzy ships both

`basecamp/fizzy`'s Gemfile pins **`lexxy 0.9.14.beta`** and it uses its
homegrown `MultiTenantable` account model **with no tenancy gem**. So a real,
shipping 37signals app combines multi-tenancy + Lexxy.

It works because Fizzy uses **shared-DB, row-level, `Current.account` scoping
with no `default_scope`** (see [`multi-tenancy.md`](./multi-tenancy.md)): rich
text and blobs are always reached through an account-scoped parent record, and
signed SGIDs can't be forged across tenants. None of the historical failure
modes apply.

---

## Recommendation for Inkwell

- **Don't try to decouple Lexxy from Active Record.** Use Action Text + Active
  Storage; Lexxy drops in as the editor.
- **Do tenancy the Fizzy way** — `Current.account` + `belongs_to :account`, reach
  rich text through parents, **no `default_scope` tenancy gem**, **no
  database-per-tenant**. That combination sidesteps every Action Text/tenancy
  problem.
- **Sharing the editor across core + client apps is trivial** — each app installs
  `@37signals/lexxy` and points at its own endpoints. The coupling is per-app
  *server* integration (Action Text + tenant-aware Active Storage), not the
  editor.

### To verify before committing
- Read how Fizzy scopes Active Storage uploads per account (the exact recipe to
  copy).
- Confirm SGID cross-tenant behavior with a test.
- Grep the Lexxy source for undocumented endpoint/resolver hooks before
  concluding custom endpoints are impossible.

## Sources
- [basecamp/lexxy](https://github.com/basecamp/lexxy) · [README roadmap](https://github.com/basecamp/lexxy/blob/main/README.md) · [attachments docs](https://basecamp.github.io/lexxy/attachments.html) · [configuration docs](https://basecamp.github.io/lexxy/configuration.html)
- [Announcing Lexxy — 37signals Dev](https://dev.37signals.com/announcing-lexxy-a-new-rich-text-editor-for-rails/)
- [basecamp/fizzy Gemfile](https://github.com/basecamp/fizzy/blob/main/Gemfile) (confirms `lexxy 0.9.14.beta` + homegrown tenancy)
