# Claims (or changes) the account's handle — the local part of the shared-lane
# sending address, <handle>@kindredquill.email. Lives on the Email tab; the
# limits (format, length, reserved words, uniqueness) are Account validations.
class Admin::HandlesController < Admin::BaseController
  def update
    if Current.account.update(handle: params[:handle])
      redirect_to admin_sending_domains_path,
        notice: "Your emails now send from #{Current.account.broadcast_address}."
    else
      redirect_to admin_sending_domains_path,
        alert: "Handle #{Current.account.errors[:handle].first}."
    end
  end
end
