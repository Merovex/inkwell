# Confirming an import: POST sends its invitations (SubscriberImportJob). Only
# an uploaded import can be confirmed, and the status flip is conditional, so a
# double-click can't queue the invitations twice.
class Admin::Subscribers::Imports::InvitationsController < Admin::BaseController
  def create
    import = Current.account.subscriber_imports.find(params[:import_id])

    if Current.account.subscriber_imports.uploaded.where(id: import.id).update_all(status: "inviting", updated_at: Time.current) == 1
      SubscriberImportJob.perform_later(import)
      redirect_to admin_subscribers_import_path(import), notice: "Sending #{helpers.pluralize(import.invitation_count, "invitation")}."
    else
      redirect_to admin_subscribers_import_path(import), alert: "This import has already been sent."
    end
  end
end
