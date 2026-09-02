# Managing the account's reader magnets — the free ebooks welcome campaigns
# hand out (attach one to a Drop on the step editor). Plain CRUD on a plain
# model: no versioning ceremony, no publish regime. Domain-admin only.
class Admin::MagnetsController < Admin::BaseController
  before_action :set_magnet, only: %i[edit update destroy]

  def index
    @magnets = Current.account.magnets.ordered
  end

  def new
    @magnet = Current.account.magnets.new
  end

  def create
    @magnet = Current.account.magnets.new(magnet_params)

    if @magnet.save
      redirect_to admin_magnets_path, notice: "Magnet saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @magnet.update(magnet_params)
      redirect_to admin_magnets_path, notice: "Magnet saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Deleting a magnet kills every outstanding claim link with it (grants
  # cascade); drops that carried it just lose their button.
  def destroy
    @magnet.destroy
    redirect_to admin_magnets_path, notice: "Magnet removed."
  end

  private
    def set_magnet
      @magnet = Current.account.magnets.find(params[:id])
    end

    def magnet_params
      params.expect(magnet: [ :title, :description, :epub, :pdf ])
    end
end
