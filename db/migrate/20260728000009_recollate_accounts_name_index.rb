class RecollateAccountsNameIndex < ActiveRecord::Migration[8.2]
  # The model validates name uniqueness case-insensitively; the column (and so
  # its unique index) was case-sensitive, which couldn't back that promise
  # under a race. Collation lives on the column — an expression index would
  # not survive the SQLite schema dump.
  def up
    change_column :accounts, :name, :string, null: false, collation: "NOCASE"
  end

  def down
    change_column :accounts, :name, :string, null: false
  end
end
