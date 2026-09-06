# Where readers come from — the BookFunnel promos, newsletter swaps and
# permanent links an author names so the roster can be counted by source
# instead of by one undifferentiated "bookfunnel". Plain account-scoped CRUD,
# domain-admin only.
#
# Creating a promotion is also the act that attributes its readers: the model
# adopts everyone who already arrived under its ref (Promotion#claim_arrivals),
# so a promo named three weeks late still gets its cohort. That's why there is
# no assign action here.
class Admin::PromotionsController < Admin::BaseController
  before_action :set_promotion, only: %i[show edit update destroy]

  def index
    @promotions = Current.account.promotions.ordered
    # Counted in SQL, one query each, rather than per row: readers per
    # promotion, and how many of those an admin attributed by hand.
    @counts = Current.account.subscribers.where.not(promotion_id: nil).group(:promotion_id).count
    @asserted = Current.account.subscribers.where.not(attributed_by_id: nil).group(:promotion_id).count
    # Tokens that brought readers in and still go by their code — the promos
    # you haven't named yet.
    @unnamed = Promotion.unnamed_refs(Current.account)
  end

  def show
    # Started from the account, not the promotion: every query on a tenanted
    # table does (ADR 0017, enforced by the tenancy guard).
    @subscribers = Current.account.subscribers.where(promotion: @promotion)
      .includes(:promotion, :attributed_by).order(created_at: :desc)
    @asserted = @subscribers.count { |subscriber| subscriber.attributed_by }
  end

  # `ref` may arrive prefilled from the index's "Name this" link.
  def new
    @promotion = Current.account.promotions.new(ref: params[:ref])
  end

  def create
    @promotion = Current.account.promotions.new(promotion_params)

    if @promotion.save
      redirect_to admin_promotion_path(@promotion), notice: "#{@promotion.title} saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @promotion.update(promotion_params)
      redirect_to admin_promotion_path(@promotion), notice: "#{@promotion.title} saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # The label goes; the readers stay, unattributed (has_many dependent: :nullify).
  def destroy
    @promotion.destroy
    redirect_to admin_promotions_path, notice: "#{@promotion.title} removed. Its readers are still on the list."
  end

  private
    def set_promotion
      @promotion = Current.account.promotions.find(params[:id])
    end

    def promotion_params
      params.expect(promotion: [ :title, :ref, :shared_on, :notes ])
    end
end
