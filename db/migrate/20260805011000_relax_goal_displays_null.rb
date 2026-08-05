# The serialized-Array coder stores an empty set as NULL (classic serialize
# behavior), so the column can't be NOT NULL; Goal#displays normalizes nil
# back to [] at the reader.
class RelaxGoalDisplaysNull < ActiveRecord::Migration[8.2]
  def change
    change_column_null :goals, :displays, true
    change_column_default :goals, :displays, from: "[]", to: nil
  end
end
