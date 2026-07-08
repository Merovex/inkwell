# Managing the board's categories: a plain lookup-table CRUD, no spine
# ceremony. Admin only — categories are install-wide vocabulary.
class Admin::CategoriesController < ApplicationController
  before_action -> { authorize! Category, to: :manage }
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
      redirect_to admin_categories_path, notice: "Category added."
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
      redirect_to admin_categories_path, notice: "Category saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # A category worn by any message version — current or historical — is
  # load-bearing history and can't be deleted, only renamed. The rescue
  # covers the race where a message claims it between the check and the
  # delete (the FK holds the line either way).
  def destroy
    if Message.exists?(category_id: @category.id)
      redirect_to admin_categories_path, alert: "That category is in use on the board, so it can't be deleted — rename it instead."
    else
      @category.destroy
      redirect_to admin_categories_path, notice: "Category deleted."
    end
  rescue ActiveRecord::InvalidForeignKey
    redirect_to admin_categories_path, alert: "That category is in use on the board, so it can't be deleted — rename it instead."
  end

  private
    def set_category
      @category = Category.find(params[:id])
    end

    def category_params
      params.expect(category: [ :icon, :name ])
    end
end
