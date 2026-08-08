class AddWordCountToBeats < ActiveRecord::Migration[8.2]
  def change
    add_column :beats, :word_count, :integer
  end
end
