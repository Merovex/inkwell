require "test_helper"

class InstallmentTest < ActiveSupport::TestCase
  test "a series and book in the same account pair up" do
    series_record, book_record = originate_series_and_book

    assert Installment.new(container_record: series_record, book_record: book_record).valid?
  end

  test "a cross-account pairing is invalid" do
    series_record, book_record = originate_series_and_book
    other = Account.create!(name: "Other Press", owner: users(:bob))
    book_record.update_column(:account_id, other.id)

    installment = Installment.new(container_record: series_record, book_record: book_record.reload)
    assert_not installment.valid?
    assert_match(/same account/, installment.errors.full_messages.to_sentence)
  end

  private
    def originate_series_and_book
      series = Record.originate(Series.new(title: "Barsoom", creator: users(:alice), body: Body.create!))
      book   = Record.originate(Book.new(title: "A Princess of Mars", creator: users(:alice), body: Body.create!))
      [ series, book ]
    end
end
