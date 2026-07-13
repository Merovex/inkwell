# Resolves the Drip's Record (the public identity — /admin/drips/:id is a Record
# id) and its current version, for the drip controllers and the nested drops
# controller (which passes the drip as :drip_id).
module DripScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Record.active.drips.find(params[:drip_id] || params[:id])
      @drip = @record.recordable
    end
end
