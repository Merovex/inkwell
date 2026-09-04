# The credential a reader-magnet partner (BookFunnel and friends) presents to
# the Sendy-compatible subscribe endpoint. Per account, because the key is what
# says WHICH list may be written: one platform-wide key would hand every author
# a credential that writes to every other author's list, and would have to be
# rotated everywhere to revoke it anywhere.
#
# Deterministically encrypted (like accounts.turnstile_secret_key, but queryable
# — the endpoint looks an account up by the key it was handed), so the unique
# index is over stable ciphertext.
class AddSendyApiKeyToAccounts < ActiveRecord::Migration[8.2]
  def change
    add_column :accounts, :sendy_api_key, :string
    add_index :accounts, :sendy_api_key, unique: true
  end
end
