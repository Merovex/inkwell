# The account picker at the bare app host root (ADR 0019), and the birth of a
# press (new/create — any signed-in user; you got in via a join code, you may
# found a press). Authentication is inherited — signed-out visitors bounce to
# sign-in. One membership skips the picker straight into that account's admin.
class AccountsController < ApplicationController
  layout "auth"

  def index
    @accounts = Current.user.accounts.order(:name)
    redirect_to admin_root_url(script_name: "/#{@accounts.first.slug}") if @accounts.one?
  end

  def new
    @account = Account.new
  end

  def create
    @account = Account.create_with_owner(name: account_params[:name], owner: Current.user)
    if @account.persisted?
      redirect_to admin_root_url(script_name: "/#{@account.slug}")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def account_params
      params.expect(account: [ :name ])
    end
end
