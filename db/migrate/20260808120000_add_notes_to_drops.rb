# Internal editorial notes on a Drop — a private memo for the drip's admins
# (reminders, A/B rationale, "revisit the CTA"), never rendered into the email
# the subscriber receives. Scalar text, so it version-copies with the Drop like
# subject/delay_days; only the rich-text body needs the build_successor carry.
class AddNotesToDrops < ActiveRecord::Migration[8.1]
  def change
    add_column :drops, :notes, :text
  end
end
