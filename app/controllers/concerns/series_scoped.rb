# Resolves the Series' Record (the public identity) and current version for
# all series-facing controllers, mirroring PostScoped.
module SeriesScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Record.active.series.find(params[:series_id] || params[:id])
      @series = @record.recordable
    end
end
