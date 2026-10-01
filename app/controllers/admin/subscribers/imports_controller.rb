# Bringing a partner's sign-up export onto the list. Create uploads and
# previews — nothing reaches the roster yet; the show page says what would
# become of each address, and Imports::InvitationsController sends the
# invitations once the admin confirms. See SubscriberImport.
class Admin::Subscribers::ImportsController < Admin::BaseController
  def new
    @import = Current.account.subscriber_imports.new(source: "storyorigin")
  end

  def create
    @import = Current.account.subscriber_imports.new(import_params)

    if @import.save
      redirect_to admin_subscribers_import_path(@import)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @import = Current.account.subscriber_imports.find(params[:id])
  end

  private
    def import_params
      params.expect(subscriber_import: [ :source, :file ])
    end
end
