# The SiteDesigner (ADR 0022, docs/site-designer.md): a two-pane editor —
# live preview iframe on the left, an option rail generated from the theme
# manifest on the right. Rails never renders site markup: the preview is a
# real Hugo build of the theme, and the rail is built from Theme#axes, so a
# vocabulary change in the theme surfaces here with no code change.
class Admin::DesignersController < Admin::BaseController
  layout "book_designer"

  def show
    @theme = Theme.current
  end
end
