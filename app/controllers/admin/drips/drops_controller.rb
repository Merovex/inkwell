# The drops (emails) inside a drip — child recordables of the Drip's Record.
# New drops append to the end; edits version the Lexxy body. Domain-admin only.
class Admin::Drips::DropsController < Admin::BaseController
  include DripScoped  # @record / @drip come from :drip_id
  before_action -> { authorize! @record, to: :manage }
  before_action :set_drop, only: %i[edit update destroy]

  def new
    @drop = Drop.new
  end

  def create
    @drop = Drop.new(drop_params.merge(event: :created))

    if @drop.valid?
      Record.originate(@drop, parent: @record)
      @drop.record.update!(position: next_position)
      redirect_to admin_drip_path(@record), notice: "Step added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    siblings = @drip.drops.to_a
    @position = siblings.index { |d| d.record_id == @drop_record.id }&.succ
    @count = siblings.size
    @step_stats = step_stats(@drop_record.id)
  end

  def update
    @drop = @drop_record.revise(event: :updated, **drop_params.to_h.symbolize_keys)

    if @drop.errors.none?
      redirect_to admin_drip_path(@record), notice: "Step saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @drop_record.trash
    redirect_to admin_drip_path(@record), notice: "Step removed."
  end

  private
    def set_drop
      @drop_record = Current.account.records.active.drops.where(parent_id: @record.id).find(params[:id])
      @drop = @drop_record.recordable
    end

    def next_position
      (Current.account.records.active.drops.where(parent_id: @record.id).maximum(:position) || 0) + 1
    end

    def drop_params
      params.expect(drop: [ :subject, :body, :delay_days, :notes, :magnet_id ]).tap do |permitted|
        # Tenant boundary: a posted magnet_id must be one of THIS account's
        # magnets — anything else (another press's id, a stale id) drops to nil.
        if permitted.key?(:magnet_id)
          permitted[:magnet_id] = Current.account.magnets.find_by(id: permitted[:magnet_id])&.id
        end
      end
    end
end
