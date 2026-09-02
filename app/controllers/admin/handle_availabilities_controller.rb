# The handle typeahead's question: is this name free? Answers with the
# normalized value's availability and — when someone else holds it — a free
# base-{4d} variant to offer instead (Account.suggest_handle). Shape/reserved
# problems come back available: false with no suggestion; the real validation
# message arrives on save.
class Admin::HandleAvailabilitiesController < Admin::BaseController
  def show
    value = Account.normalize_value_for(:handle, params[:value].to_s)
    render json: availability(value)
  end

  private
    def availability(value)
      return { available: false } if value.blank?
      return { available: true, mine: true } if Current.account.handle == value

      if Account.where.not(id: Current.account.id).exists?(handle: value)
        { available: false, taken: true, suggestion: Account.suggest_handle(value) }
      else
        acceptable = value.length.between?(3, 30) &&
          value.match?(Account::HANDLE_FORMAT) &&
          !Account::RESERVED_HANDLES.include?(value)
        { available: acceptable }
      end
    end
end
