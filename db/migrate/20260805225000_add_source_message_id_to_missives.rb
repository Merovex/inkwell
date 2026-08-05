# Mail-in support (SupportMailbox): the inbound email's Message-ID, stored so a
# redelivered SNS notification can't create a duplicate Missive. Nil for
# contact-form submissions.
class AddSourceMessageIdToMissives < ActiveRecord::Migration[8.2]
  def change
    add_column :missives, :source_message_id, :string
    add_index :missives, :source_message_id, unique: true, where: "source_message_id IS NOT NULL"
  end
end
