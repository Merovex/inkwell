# Membership: which users may work inside an account's admin. Deliberately
# role-free — the global users.role stays authoritative until per-account
# roles are a real feature (ADR 0017). Uniqueness is the DB index's job.
class AccountUser < ApplicationRecord
  belongs_to :account
  belongs_to :user
end
