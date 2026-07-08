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
    post admin_books_path, params: { book: { title: "Shown Book", content: "x" }, publish: "1" }
    record = Record.books.order(:id).last

    get admin_books_path
    assert_response :success
    assert_select ".list__title", text: "Shown Book"

    get admin_book_path(record)
    assert_response :success
    assert_select "h1", text: "Shown Book"
    # editable title, change-log menu link, and a cover placeholder
    assert_select "[data-controller=editable] h1[data-action*=?]", "editable#edit"
    assert_select "a[href=?]", admin_book_events_path(record), text: "Change log"
    assert_select ".book-detail__cover--empty"
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

  test "new and edit render the composer, date picker, cover upload and series typeahead" do
    get new_admin_book_path
    assert_response :success
    assert_select "form#composer"
    assert_select "duet-date-picker[name=?]", "book[publication_date]"

    post admin_books_path, params: { book: { title: "Editable", content: "x" } }
    record = Record.books.order(:id).last
    get edit_admin_book_path(record)
    assert_response :success
    assert_select "form#composer"
    assert_select "input[type=file][name=depiction]"
    assert_select "[data-controller=combobox]"
    assert_select "ul#book_series"
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
        params: { series_record_id: series.id, book_record_id: book.id, context: "book" }
    end
    installment = Installment.find_by(series_record_id: series.id, book_record_id: book.id)
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

    post admin_installments_path, as: :turbo_stream, params: { series_record_id: series.id, book_record_id: b1.id, context: "series" }
    post admin_installments_path, as: :turbo_stream, params: { series_record_id: series.id, book_record_id: b2.id, context: "series" }

    patch reorder_admin_series_path(series), params: { book_record_ids: [ b2.id, b1.id ] }
    assert_response :no_content
    assert_equal 1, Installment.find_by(series_record_id: series.id, book_record_id: b2.id).position
    assert_equal 2, Installment.find_by(series_record_id: series.id, book_record_id: b1.id).position
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
