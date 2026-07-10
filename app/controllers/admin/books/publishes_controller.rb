# Publishing a book as a resource: POST publishes, DELETE reverts to draft.
class Admin::Books::PublishesController < Admin::BaseController
  include BookScoped
  before_action -> { authorize! @record, to: :manage }

  def create
    @book.publish
    redirect_to admin_book_path(@record), notice: "Book published."
  end

  def destroy
    @book.unpublish
    redirect_to admin_book_path(@record), notice: "Book reverted to a draft."
  end
end
