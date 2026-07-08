require "test_helper"

class SeriesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:alice) }

  test "create, index, new, show and edit render" do
    get new_admin_series_path
    assert_response :success
    assert_select "form#composer"

    assert_difference -> { Record.series.count }, 1 do
      post admin_series_index_path, params: { series: { title: "My Series", content: "About" }, publish: "1" }
    end
    record = Record.series.order(:id).last
    assert_redirected_to admin_series_path(record)

    get admin_series_index_path
    assert_response :success
    assert_select ".list__title", text: "My Series"

    get admin_series_path(record)
    assert_response :success
    assert_select "h1", text: "My Series"
    assert_select ".series-books"

    get edit_admin_series_path(record)
    assert_response :success
    assert_select "form#composer"
  end

  test "the series show lists its books, with a typeahead to add more" do
    post admin_series_index_path, params: { series: { title: "S", content: "x" }, publish: "1" }
    series = Record.series.order(:id).last
    post admin_books_path, params: { book: { title: "First", content: "x" }, publish: "1" }
    first = Record.books.order(:id).last
    post admin_books_path, params: { book: { title: "Second", content: "x" }, publish: "1" }
    second = Record.books.order(:id).last
    [ first, second ].each do |book|
      post admin_installments_path, as: :turbo_stream, params: { series_record_id: series.id, book_record_id: book.id, context: "series" }
    end

    get admin_series_path(series)
    assert_response :success
    assert_select ".sortable__item", count: 2
    assert_select "[data-controller=combobox]"
  end
end
