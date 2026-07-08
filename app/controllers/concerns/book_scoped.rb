# Resolves the Book's Record (the public identity) and current version for all
# book-facing controllers, mirroring PostScoped.
module BookScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Record.active.books.find(params[:book_id] || params[:id])
      @book = @record.recordable
    end
end
