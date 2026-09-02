# Self-registration behind a join code: a valid code (the inviter's rotatable
# Crockford string) creates the User — or reuses an existing one — and sends a
# sign-up magic link. Account creation happens later, by the signed-in user
# (AccountsController); Basecamp-style, the email proves itself before anything
# tenant-shaped exists. New users record who vouched for them (inviter).
class Signup
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email_address, :string
  attribute :invite_code, :string

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :invite_code, presence: true

  attr_reader :user

  def save
    return false unless valid?

    join_code = JoinCode.lookup(invite_code)
    unless join_code
      errors.add(:invite_code, "isn't valid")
      return false
    end

    @user = User.with_email_address(email_address) ||
      User.new(email_address: email_address, inviter: join_code.user)
    if @user.persisted? || @user.save
      @user.send_magic_link(purpose: :sign_up)
      true
    else
      errors.merge!(@user.errors)
      false
    end
  end
end
