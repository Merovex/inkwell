# Resolves the standing page behind /admin/pages/:slug — the slug is the
# page's permanent identity (it lives on the Record), so unlike posts the
# backend addresses it by name rather than by record id.
module PageScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_page
  end

  private
    def set_page
      @record = Current.account.records.active.pages.find_by!(slug: params[:page_slug] || params[:slug])
      @page = @record.recordable
    end
end
