# The account picker at the bare app host root (ADR 0019). Authentication is
# inherited — a signed-out visitor bounces to sign-in. One membership skips
# the ceremony and lands straight in that account's admin; several get cards.
class AccountsController < ApplicationController
  layout "auth"

  def index
    @accounts = Current.user.accounts.order(:name)
    redirect_to admin_root_url(script_name: "/#{@accounts.first.slug}") if @accounts.one?
  end
end
