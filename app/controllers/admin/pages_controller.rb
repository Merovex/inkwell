# The site's standing pages: About, Privacy, Terms, and the invitation that
# sits above the newsletter signup. Every account is seeded with the four
# (Account#seed_pages) and the set is fixed — so this is edit-and-publish
# only, with no new/create/destroy to route.
class Admin::PagesController < Admin::BaseController
  include PageScoped
  skip_before_action :set_page, only: :index
  before_action -> { authorize! @record, to: :manage }, only: %i[edit update]

  def index
    # Four rows in the order Page::MANDATORY declares them (About first, the
    # legal pair last) — an ordering that lives in Ruby, not in a column.
    pages = Current.account.pages.includes(:record, body: :rich_text_content)
    @pages = pages.sort_by { |page| Page::MANDATORY.keys.index(page.slug) || Page::MANDATORY.size }
  end

  def edit
  end

  # Published pages version on every save, drafts amend in place — the same
  # ladder as posts, in Record#save_edit.
  def update
    @page = @record.save_edit(**page_params.to_h.symbolize_keys)

    if @page.errors.none?
      redirect_to admin_pages_path, notice: "Page saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def page_params
      params.expect(page: [ :title, :content ])
    end
end
