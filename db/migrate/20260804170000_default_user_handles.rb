# Names become handles: unique, never blank. Backfill nameless users from
# their email's local part, de-dupe any existing collisions with a 4-digit
# discriminator (first holder keeps the plain name), then lock it in with a
# unique index. Mirrors User::Registration.generate_handle, inlined so the
# migration doesn't lean on app code.
class DefaultUserHandles < ActiveRecord::Migration[8.2]
  class MigratedUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    seen = Set.new
    MigratedUser.order(:id).each do |user|
      base = user.name.presence ||
        user.email_address.to_s.split("@").first.to_s.split("+").first
            .downcase.gsub(/[^a-z0-9._]/, "").presence || "member"
      candidate = base
      candidate = "#{base}#{rand(1000..9999)}" while seen.include?(candidate.downcase)
      seen << candidate.downcase
      user.update_columns(name: candidate) if candidate != user.name
    end
    add_index :users, :name, unique: true
  end

  def down
    remove_index :users, :name
  end
end
