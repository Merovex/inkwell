# The book cover as a resource. Uploading mints a fresh Depiction and routes it
# through the record's save regime (save_edit): a new version for a published
# book — so the cover joins its history — or an in-place amend for a draft.
# Removing points the current version at no cover the same way.
class Admin::Books::DepictionsController < Admin::BaseController
  include BookScoped
  before_action -> { authorize! @record, to: :manage }

  def create
    depiction = Depiction.new
    depiction.image.attach(params[:depiction]) if params[:depiction].present?

    if depiction.image.attached? && depiction.save
      @record.save_edit(depiction: depiction)
      redirect_to edit_admin_book_path(@record), notice: "Cover uploaded."
    else
      redirect_to edit_admin_book_path(@record), alert: "Please choose an image file."
    end
  end

  def destroy
    @record.save_edit(depiction: nil)
    redirect_to edit_admin_book_path(@record), notice: "Cover removed."
  end
end
