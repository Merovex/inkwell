# The SiteDesigner (ADR 0022, docs/site-designer.md): a two-pane editor —
# live preview iframe on the left, an option rail generated from the theme
# manifest on the right. Rails never renders site markup: the preview is a
# real Hugo build of the theme, and the rail is built from Theme#axes, so a
# vocabulary change in the theme surfaces here with no code change.
class Admin::DesignersController < Admin::BaseController
  layout "book_designer"

  def show
    @theme = Theme.current
    # Without a provisioned theme manifest there's no option rail to render;
    # degrade to a clear notice instead of 500ing deep in the view (Theme#axes).
    return render :unavailable, layout: false, status: :service_unavailable unless @theme.available?

    # The hero content editor's featured-book picker: same published scope
    # the exporter snapshots, so the picker offers exactly what can render.
    @books = Current.account.books.published.feed_ordered
  end

  # Save-to-account: the working design graduates from the browser to the
  # account, where the next real build reads it. Validated by the same
  # SiteDesign the preview uses — a design that wouldn't preview can't be
  # saved. Save is deliberate (never autosave): idle edits must not
  # republish a live site.
  def update
    Current.account.update!(design: SiteDesign.new(params).to_h)
    head :no_content
  rescue SiteDesign::Invalid => error
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
