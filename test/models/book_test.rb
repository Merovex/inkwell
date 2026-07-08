require "test_helper"

class BookTest < ActiveSupport::TestCase
  setup { @user = users(:alice) }

  def create_book(**attrs)
    book = Book.new({ title: "A Book", event: :created, status: :published,
      published_at: Time.current, creator: @user }.merge(attrs))
    Record.originate(book)
    book
  end

  def create_series(**attrs)
    series = Series.new({ title: "A Series", event: :created, status: :published,
      published_at: Time.current, creator: @user }.merge(attrs))
    Record.originate(series)
    series
  end

  def attach_cover(byte = "x")
    Depiction.create!.tap { |d| d.image.attach(io: StringIO.new(byte), filename: "c.png", content_type: "image/png") }
  end

  test "a book is a publishable recordable with a publication_date" do
    book = create_book(publication_date: Date.new(2024, 1, 1))
    assert book.published?
    assert_equal book, book.record.recordable
    assert_equal Date.new(2024, 1, 1), book.publication_date
  end

  test "a series orders its books by installment position; a book knows its series" do
    series = create_series
    b1 = create_book(title: "One")
    b2 = create_book(title: "Two")
    Installment.create!(series_record_id: series.record_id, book_record_id: b2.record_id, position: 2)
    Installment.create!(series_record_id: series.record_id, book_record_id: b1.record_id, position: 1)

    assert_equal %w[One Two], series.books.map(&:title)
    assert_equal [ series.record_id ], b1.series.map(&:record_id)
  end

  test "a book can belong to more than one series" do
    s1 = create_series(title: "S1")
    s2 = create_series(title: "S2")
    book = create_book
    Installment.create!(series_record_id: s1.record_id, book_record_id: book.record_id, position: 1)
    Installment.create!(series_record_id: s2.record_id, book_record_id: book.record_id, position: 1)

    assert_equal 2, book.series.count
  end

  test "a text-only edit of a published book versions but shares the cover" do
    book = create_book
    book.record.save_edit(creator: @user, depiction: attach_cover)
    assert book.record.reload.recordable.cover?
    depiction_id = book.record.recordable.depiction_id

    assert_difference -> { book.record.versions.count }, 1 do
      book.record.save_edit(creator: @user, title: "Renamed")
    end
    assert_equal depiction_id, book.record.reload.recordable.depiction_id,
      "the unchanged cover carries forward by id"
  end

  test "swapping the cover on a published book versions the cover" do
    book = create_book
    d1 = attach_cover("1")
    book.record.save_edit(creator: @user, depiction: d1)
    first = book.record.reload.recordable

    d2 = attach_cover("2")
    book.record.save_edit(creator: @user, depiction: d2)
    current = book.record.reload.recordable

    assert_not_equal first.id, current.id, "a new version was minted"
    assert_equal d1.id, first.depiction_id, "the old version keeps its old cover"
    assert_equal d2.id, current.depiction_id, "the current version points at the new cover"
  end

  test "destroying a book record clears its installments" do
    series = create_series
    book = create_book
    Installment.create!(series_record_id: series.record_id, book_record_id: book.record_id, position: 1)

    assert_difference -> { Installment.count }, -1 do
      book.record.destroy
    end
  end
end
