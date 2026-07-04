# Resolves the Record (the public identity — /forum/:id is a Record id, never
# a version id) and its current version for all message-facing controllers.
module MessageScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Record.active.messages.find(params[:message_id] || params[:id])
      @message = @record.recordable
    end
end
