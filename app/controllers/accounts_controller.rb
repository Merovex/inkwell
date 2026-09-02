# The account picker at the bare app host root (ADR 0019), and the birth of a
# site (new/create — any signed-in user; you got in via a join code, you may
# found a site). Authentication is inherited — signed-out visitors bounce to
# sign-in. One membership skips the picker straight into that account's admin.
class AccountsController < ApplicationController
  layout "auth"

  def index
    @accounts = Current.user.accounts.order(:name)
    # No site yet? The app shell (circles) is home — a new member should never
    # meet a bare picker; site creation waits in the app menu when they're ready.
    return redirect_to circles_path if @accounts.none?
    redirect_to @accounts.first.admin_path if @accounts.one?
  end

  def new
    @account = Account.new
  end

  def create
    @account = Account.create_with_owner(name: account_params[:name], owner: Current.user)
    if @account.persisted?
      redirect_to @account.admin_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def account_params
      params.expect(account: [ :name ])
    end
end
