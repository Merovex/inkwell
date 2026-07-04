# Managing the board's categories: a plain lookup-table CRUD, no spine
# ceremony. Anyone can tend the list, Basecamp style.
class CategoriesController < ApplicationController
  before_action :set_category, only: %i[edit update destroy]

  def index
    @categories = Category.ordered
  end

  def new
    @category = Category.new
  end

  def create
    @category = Category.new(category_params)

    if @category.save
      redirect_to categories_path, notice: "Category added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Renames flow through everywhere instantly — messages reference the
  # category by id, history included.
  def update
    if @category.update(category_params)
      redirect_to categories_path, notice: "Category saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # A category worn by any message version — current or historical — is
  # load-bearing history and can't be deleted, only renamed.
  def destroy
    if Message.exists?(category_id: @category.id)
      redirect_to categories_path, alert: "That category is in use on the board, so it can't be deleted — rename it instead."
    else
      @category.destroy
      redirect_to categories_path, notice: "Category deleted."
    end
  end

  private
    def set_category
      @category = Category.find(params[:id])
    end

    def category_params
      params.expect(category: [ :icon, :name ])
    end
end
