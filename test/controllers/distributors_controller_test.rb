require "test_helper"

class DistributorsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:alice) }

  def create_book
    post admin_books_path, params: { book: { title: "B", content: "x" }, publish: "1" }
    Record.books.order(:id).last
  end

  def create_series
    post admin_series_index_path, params: { series: { title: "S", content: "x" }, publish: "1" }
    Record.series.order(:id).last
  end

  test "add a buy link to a book, detecting the platform and cleaning the url" do
    book = create_book
    assert_difference -> { Distributor.count }, 1 do
      post admin_distributors_path, as: :turbo_stream,
        params: { record_id: book.id, url: "https://www.amazon.com/dp/B0XYZ?tag=x" }
    end
    distributor = Distributor.last
    assert_equal book.id, distributor.record_id
    assert_equal "amazon", distributor.platform
    assert_equal "https://www.amazon.com/dp/B0XYZ", distributor.url
  end

  test "a series can also have a buy link" do
    series = create_series
    assert_difference -> { Distributor.count }, 1 do
      post admin_distributors_path, as: :turbo_stream, params: { record_id: series.id, url: "https://www.kobo.com/x" }
    end
    assert_equal "kobo", Distributor.last.platform
  end

  test "a duplicate url on the same record is rejected without creating" do
    book = create_book
    post admin_distributors_path, as: :turbo_stream, params: { record_id: book.id, url: "https://www.kobo.com/x" }
    assert_no_difference -> { Distributor.count } do
      post admin_distributors_path, as: :turbo_stream, params: { record_id: book.id, url: "https://www.kobo.com/x" }
    end
  end

  test "adding a link to a published book records it in the change log" do
    book = create_book
    assert_difference -> { book.versions.count }, 1 do
      post admin_distributors_path, as: :turbo_stream, params: { record_id: book.id, url: "https://www.kobo.com/x" }
    end
    assert_equal "link_added", book.reload.recordable.event

    get admin_book_events_path(book)
    assert_select ".history__entry", text: /distributor link/
  end

  test "adding a link to a draft does not mint a version" do
    post admin_books_path, params: { book: { title: "Draft", content: "x" } }
    book = Record.books.order(:id).last
    assert_no_difference -> { book.versions.count } do
      post admin_distributors_path, as: :turbo_stream, params: { record_id: book.id, url: "https://www.kobo.com/x" }
    end
  end

  test "removing a buy link" do
    book = create_book
    distributor = book.distributors.create!(url: "https://www.lulu.com/x")
    assert_difference -> { Distributor.count }, -1 do
      delete admin_distributor_path(distributor), as: :turbo_stream
    end
  end

  test "distributors are managed from the show page, not edit" do
    book = create_book
    book.distributors.create!(url: "https://www.smashwords.com/x")

    get admin_book_path(book)
    assert_response :success
    assert_select "form.distributor-form"
    assert_select "#record_distributors .mrow", text: /Smashwords/

    get edit_admin_book_path(book)
    assert_response :success
    assert_select ".distributors", count: 0
  end
end
