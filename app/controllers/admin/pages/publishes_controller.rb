# Publishing a standing page as a resource: POST publishes, DELETE takes it
# back off the site. Both are event versions on the page's history, and both
# rebuild the static site.
class Admin::Pages::PublishesController < Admin::BaseController
  include PageScoped
  before_action -> { authorize! @record, to: :manage }

  def create
    @page.publish
    redirect_to admin_pages_path, notice: "#{@page.title} published."
  end

  def destroy
    @page.unpublish
    redirect_to admin_pages_path, notice: "#{@page.title} reverted to a draft — it's off the public site."
  end
end
