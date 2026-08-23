# The delivery ledger gains the one cross-site identity (ADR 0027): the Person
# behind the recipient address. recipient was a bare string and
# people.email_address is unique, so the backfill is a lookup — and the rows
# that had no subscriber to act on (confirmation-email bounces carry no
# delivery tags) become actionable by identity.
class AddPersonToDeliveryEvents < ActiveRecord::Migration[8.2]
  def change
    add_reference :delivery_events, :person, null: true, index: true

    reversible do |direction|
      direction.up do
        DeliveryEvent.reset_column_information
        DeliveryEvent.where(person_id: nil).where.not(recipient: [ nil, "" ]).find_each do |event|
          person = Person.find_by(email_address: Person.normalize_value_for(:email_address, event.recipient))
          event.update_columns(person_id: person.id) if person
        end
      end
    end
  end
end
