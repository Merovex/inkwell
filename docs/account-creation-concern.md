# Alcovo — Account Creation, as a Separate Concern

*Notional design. Keeps the "a person creates an account" flow **out of the core
`Account` model** and isolated in its own concern + a form object — mirroring how
Fizzy separates `Signup` (form object) from `Account.create_with_owner`.
Companion to [`fizzy-user-account-model.md`](./fizzy-user-account-model.md) and
[`data-model.md`](./data-model.md).*

Naming (Alcovo): `Person` (Fizzy's `Identity`) / `User` / `Account` — see the
vocabulary decision in [ADR 0002](decisions/0002-domain-vocabulary-person-user-account.md).

---

## 1. Why a separate concern

In [`fizzy-user-account-model.md`](./fizzy-user-account-model.md) we deliberately
**excluded** the birth-of-an-account path from the core model, because it's a
different kind of code: the steady-state `Account` model is about *being* an
account, while creation is a one-shot orchestration (make the account, mint the
owner user, seed defaults, wire up the login). Mixing them bloats the model and
couples "exists" with "how it came to exist."

Fizzy keeps these apart too:
- **`Signup`** — an `ActiveModel` form object: holds `full_name` /
  `email_address`, finds-or-creates the `Person` (Fizzy: `Identity`), sends a
  magic link, then on `complete` calls into the account layer and cleans up on
  failure.
- **`Account.create_with_owner`** — the DB-level "make the account + its owner
  user + system user" transaction.

We split the same way, but push the `create_with_owner` logic into an explicit
**concern** (`Account::Foundable`) rather than leaving it loose on the model, so
the core `Account` class stays about membership/tenancy and the founding logic is
opt-in and self-contained.

```
Person ──(fills in)──▶ Signup (form object) ──▶ Account::Foundable.create_with_owner
                            │                          │
                            ├─ find/create Person      ├─ create Account
                            ├─ send magic link         ├─ create System user
                            └─ on failure: destroy     └─ create Owner user (verified)
```

---

## 2. The concern: `Account::Foundable`

Extracted, self-contained founding logic. `include Account::Foundable` into
`Account`; the core model file never mentions creation.

```ruby
# app/models/account/foundable.rb
module Account::Foundable
  extend ActiveSupport::Concern

  class_methods do
    # Create an account together with its automated System user and its human
    # Owner user, atomically. `owner` is a Person.
    def create_with_owner(name:, owner:, seed: true)
      transaction do
        create!(name: name).tap do |account|
          account.users.create!(role: :system, name: "System")
          account.users.create!(
            person:      owner,
            name:        owner.name.presence || owner.email_address,
            role:        :owner,
            verified_at: Time.current
          )
          account.seed_defaults if seed
        end
      end
    end
  end

  # Default boards/docs a brand-new account starts with. Kept here (creation-time
  # only) rather than on the core model.
  def seed_defaults
    message_boards.create!(name: "Workshop", position: 1)
    message_boards.create!(name: "Announcements", position: 2)
    questionnaires.create!(name: "Automatic Check-ins")
    vaults.create!(name: "Docs & Files")
    chats.create!(name: "Chat")
  end
end
```

Notes:
- **Atomic** — the whole founding is wrapped in a `transaction`; a failure
  anywhere rolls back the half-built account (Fizzy's `Signup#complete` instead
  destroys the account on error; a transaction is cleaner when there's no
  external side effect mid-way).
- **System user first**, then the owner — matches Fizzy's `create_with_owner`
  (system user + owner user). The system user is the automated actor for
  background/webhook actions; it's excluded from "active" members by the role
  scopes.
- **Owner is `verified_at: Time.current`** — the founder is trusted implicitly;
  no verification round-trip.
- **`seed` is a flag**, so tests / imports can create bare accounts
  (`seed: false`), exactly like Fizzy's `skip_account_seeding`.

---

## 3. The entry point: `Signup` form object

The user-facing flow. Not an AR model — an `ActiveModel` form object that owns
validation, the magic-link send, and the call into `Account::Foundable`. This is
what a `SignupsController#create` instantiates.

```ruby
# app/models/signup.rb
class Signup
  include ActiveModel::Model, ActiveModel::Attributes

  attribute :full_name,     :string
  attribute :email_address, :string
  attribute :account_name,  :string
  attribute :skip_seeding,  :boolean, default: false

  attr_reader :person, :account, :user

  validates :full_name,    presence: true, length: { maximum: 100 }
  validates :account_name, presence: true, length: { maximum: 100 }
  validate  :person_present, on: :complete

  # Step 1 — identify the human and start the passwordless flow.
  def begin
    return false unless valid?(:begin)

    @person = Person.find_or_create_by!(email_address: email_address)
    @person.send_magic_link(for: :signup)
    true
  end

  # Step 2 — after the magic link is confirmed, found the account.
  def complete
    return false unless valid?(:complete)

    @account = Account.create_with_owner(
      name:  account_name,
      owner: person,
      seed:  !skip_seeding
    )
    @user = @account.users.owner.first
    true
  rescue ActiveRecord::RecordInvalid => e
    @account&.destroy
    errors.add(:base, "Could not create account: #{e.message}")
    false
  end

  private
    def person_present
      errors.add(:person, "must confirm their email first") if person.nil?
    end
end
```

Notes:
- **Two-phase, mirroring Fizzy** (`create_identity` → `complete`): first prove
  the email via magic link, *then* found the account. The account isn't created
  until the founder's address is confirmed.
- **`valid?(:begin)` / `valid?(:complete)`** — validation contexts split the two
  phases (name/email checked up front; `person` presence only at completion).
- **Belt-and-suspenders cleanup** — the concern's transaction handles rollback,
  but `complete` also rescues and destroys any partial account, matching Fizzy's
  defensive `destroy_account`.

---

## 4. What the core `Account` model keeps vs. delegates

| Concern | Lives in |
|---------|----------|
| Associations, tenant lifecycle (`active?`, cancellation), `system_user`, `slug` | **core `Account`** (see user/account doc) |
| `create_with_owner`, `seed_defaults` | **`Account::Foundable`** (this concern) |
| Email capture, magic-link send, two-phase orchestration, error cleanup | **`Signup`** form object |

So `app/models/account.rb` stays about *being* an account and only carries
`include Account::Foundable` — the founding code is one file you can read,
test, or replace in isolation.

---

## 5. Open decisions

1. **Concern vs. plain class method.** Fizzy leaves `create_with_owner` directly
   on `Account`. We extract to a concern for separation; if the founding logic
   stays tiny, inlining it on `Account` is also defensible. Chosen: concern, for
   the stated isolation.
2. **Transaction vs. destroy-on-error.** We use a DB transaction *and* a rescue.
   If `seed_defaults` ever does external work (e.g. provisioning storage), the
   transaction won't cover it — revisit then.
3. **Magic link before or after account creation.** Chosen: before (confirm
   email, then found). Alternative is create-then-verify, which risks orphan
   accounts.
4. **First user role.** Founder = `owner`, auto-verified. If accounts should
   support co-founders, that's a post-creation invite flow, not this concern.

---

*Grounded in Fizzy's `Signup` form object + `Account.create_with_owner`
(`basecamp/fizzy@main`); the Alcovo code above is notional design, not copied
source.*

## Sources
- [signup.rb](https://github.com/basecamp/fizzy/blob/main/app/models/signup.rb)
- [account.rb](https://github.com/basecamp/fizzy/blob/main/app/models/account.rb)
- [account/seedeable.rb](https://github.com/basecamp/fizzy/blob/main/app/models/account/seedeable.rb)
