require "test_helper"

class BooksControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:alice) }

  test "create a draft book with a publication_date, then publish it" do
    assert_difference -> { Record.books.count }, 1 do
      post admin_books_path, params: { book: { title: "New Book", content: "Blurb", publication_date: "2024-02-01" } }
    end
    record = Record.books.order(:id).last
    assert_redirected_to admin_book_path(record)
    assert record.recordable.drafted?
    assert_equal Date.new(2024, 2, 1), record.recordable.publication_date

    post admin_book_publish_path(record)
    assert record.reload.recordable.published?
  end

  test "index and show render" do
    post admin_books_path, params: { book: { title: "Shown Book", content: "x", word_count: "50000" }, publish: "1" }
    record = Record.books.order(:id).last

    get admin_books_path
    assert_response :success
    assert_select ".book-card__title", text: "Shown Book"
    assert_select ".book-shelf__title", text: "Standalone"
    assert_select ".book-card__meta", text: /50k/   # abbreviated word count on the card
    assert_select "[data-controller=filter] .filter-by-text__input"

    get admin_book_path(record)
    assert_response :success
    assert_select "h1", text: "Shown Book"
    # editable title (a real button inside the h1 — keyboard-operable),
    # change-log menu link, and a cover placeholder
    assert_select "[data-controller=editable] h1 button[data-action*=?]", "editable#edit"
    assert_select "a[href=?]", admin_book_events_path(record), text: "Change log"
    assert_select ".cover-drop"   # click/drop cover uploader (no cover yet)
  end

  test "the detail page carries the tagline, length, and ISBN" do
    post admin_books_path, params: { book: {
      title: "Bellicose", content: "About the book.",
      tagline: "The orphaned Danel struggles to find his way.",
      word_count: "112400", isbn: "978-1-234-56789", publication_date: "2022-09-01" }, publish: "1" }
    record = Record.books.order(:id).last

    book = record.recordable
    assert_equal 112400, book.word_count
    assert_equal "978-1-234-56789", book.isbn
    assert_equal "The orphaned Danel struggles to find his way.", book.tagline

    get admin_book_path(record)
    assert_response :success
    assert_select ".book-detail__tagline", text: /orphaned Danel/
    assert_select ".book-stats", text: /112,400 words/
    assert_select ".book-stats", text: /978-1-234-56789/
  end

  test "the change log renders the version history" do
    post admin_books_path, params: { book: { title: "Original", content: "x" }, publish: "1" }
    record = Record.books.order(:id).last
    patch admin_book_path(record), params: { book: { title: "Renamed", content: "x" } }

    get admin_book_events_path(record)
    assert_response :success
    assert_select "h1", text: "Change Log"
    assert_select ".history__entry", minimum: 2
    assert_select "a[href=?]", admin_book_change_path(record, record.versions.first)
  end

  test "adding a cover to a published book records it in the change log" do
    post admin_books_path, params: { book: { title: "Covered", content: "x" }, publish: "1" }
    record = Record.books.order(:id).last
    post admin_book_depiction_path(record), params: { depiction: fixture_file_upload("avatar.png", "image/png") }

    get admin_book_events_path(record)
    assert_response :success
    assert_select ".history__entry", text: /cover/
  end

  test "edit is just the blurb; cover, series and distributors are managed on show" do
    get new_admin_book_path
    assert_response :success
    assert_select "form#composer"
    assert_select "duet-date-picker[name=?]", "book[publication_date]"

    post admin_books_path, params: { book: { title: "Editable", content: "x" } }
    record = Record.books.order(:id).last

    get edit_admin_book_path(record)
    assert_response :success
    assert_select "form#composer"
    # cover, series, and distributors all live on show now
    assert_select "input[type=file][name=depiction]", count: 0
    assert_select "[data-controller=combobox]", count: 0

    get admin_book_path(record)
    assert_select "input[type=file][name=depiction]"   # click/drop cover uploader
    assert_select "[data-controller=combobox]"         # series typeahead
    assert_select "ul#book_series"
    assert_select "form.distributor-form"              # distributors
  end

  test "series search returns current series matching the query" do
    post admin_series_index_path, params: { series: { title: "Postal Marines", content: "x" }, publish: "1" }
    post admin_series_index_path, params: { series: { title: "Strand", content: "x" }, publish: "1" }

    get search_admin_series_index_path(q: "postal")
    assert_response :success
    assert_select "li[role=option]", text: /Postal Marines/
    assert_select "li[role=option]", text: /Strand/, count: 0
  end

  test "adding then removing a series membership via installments" do
    post admin_series_index_path, params: { series: { title: "S", content: "x" }, publish: "1" }
    series = Record.series.order(:id).last
    post admin_books_path, params: { book: { title: "B", content: "x" }, publish: "1" }
    book = Record.books.order(:id).last

    assert_difference -> { Installment.count }, 1 do
      post admin_installments_path, as: :turbo_stream,
        params: { container_record_id: series.id, book_record_id: book.id, context: "book_series" }
    end
    installment = Installment.find_by(container_record_id: series.id, book_record_id: book.id)
    assert installment, "installment was created"

    assert_difference -> { Installment.count }, -1 do
      delete admin_installment_path(installment), as: :turbo_stream
    end
  end

  test "reorder rewrites installment positions for the series" do
    post admin_series_index_path, params: { series: { title: "S", content: "x" }, publish: "1" }
    series = Record.series.order(:id).last
    post admin_books_path, params: { book: { title: "B1", content: "x" }, publish: "1" }
    b1 = Record.books.order(:id).last
    post admin_books_path, params: { book: { title: "B2", content: "x" }, publish: "1" }
    b2 = Record.books.order(:id).last

    post admin_installments_path, as: :turbo_stream, params: { container_record_id: series.id, book_record_id: b1.id, context: "series" }
    post admin_installments_path, as: :turbo_stream, params: { container_record_id: series.id, book_record_id: b2.id, context: "series" }

    patch reorder_admin_series_path(series), params: { book_record_ids: [ b2.id, b1.id ] }
    assert_response :no_content
    assert_equal 1, Installment.find_by(container_record_id: series.id, book_record_id: b2.id).position
    assert_equal 2, Installment.find_by(container_record_id: series.id, book_record_id: b1.id).position
  end

  test "moving a book to another series reassigns the installment and renumbers" do
    post admin_series_index_path, params: { series: { title: "Postal Marines", content: "x" }, publish: "1" }
    from = Record.series.order(:id).last
    post admin_series_index_path, params: { series: { title: "Strand", content: "x" }, publish: "1" }
    to = Record.series.order(:id).last

    post admin_books_path, params: { book: { title: "Bellicose", content: "x" }, publish: "1" }
    book = Record.books.order(:id).last
    post admin_books_path, params: { book: { title: "Wampum", content: "x" }, publish: "1" }
    other = Record.books.order(:id).last

    post admin_installments_path, as: :turbo_stream, params: { container_record_id: from.id, book_record_id: book.id, context: "book_series" }
    post admin_installments_path, as: :turbo_stream, params: { container_record_id: to.id, book_record_id: other.id, context: "series" }

    get new_admin_book_shelving_path(book)
    assert_response :success
    assert_select "input[type=radio][name=container_record_id]", minimum: 3   # two series + standalone

    # Move it into Strand: it lands at the end (position 2), and Postal Marines
    # is left empty.
    post admin_book_shelving_path(book), params: { container_record_id: to.id }
    assert_redirected_to admin_book_path(book)
    assert_nil Installment.find_by(container_record_id: from.id, book_record_id: book.id)
    moved = Installment.find_by(container_record_id: to.id, book_record_id: book.id)
    assert_equal 2, moved.position

    # Move it to standalone: the series installment is gone entirely.
    assert_difference -> { Installment.where(book_record_id: book.id).count }, -1 do
      post admin_book_shelving_path(book), params: { container_record_id: "" }
    end
  end

  test "uploading a cover attaches a versioned depiction to the current version" do
    post admin_books_path, params: { book: { title: "Cover Book", content: "x" }, publish: "1" }
    record = Record.books.order(:id).last

    assert_difference -> { Depiction.count }, 1 do
      post admin_book_depiction_path(record),
        params: { depiction: fixture_file_upload("avatar.png", "image/png") }
    end
    assert record.reload.recordable.cover?
  end
end
