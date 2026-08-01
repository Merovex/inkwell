# Resolves the Collection's Record (the public identity) and current version for
# all collection-facing controllers, mirroring SeriesScoped.
module CollectionScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Current.account.records.active.collections.find(params[:collection_id] || params[:id])
      @collection = @record.recordable
    end
end
