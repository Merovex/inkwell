require "test_helper"

class SignInCodeTest < ActiveSupport::TestCase
  setup { @user = users(:alice) }

  test "creating a code generates an 8-letter plaintext and stores only its digest" do
    code = @user.sign_in_codes.create!

    assert_match(/\A[A-Z]{8}\z/, code.plaintext)
    assert_equal SignInCode.digest(code.plaintext), code.code_digest
    assert_not_includes code.code_digest, code.plaintext
    assert code.expires_at > Time.current
  end

  test "format groups the code as ABCD-EFGH" do
    assert_equal "ABCD-EFGH", SignInCode.format("ABCDEFGH")
  end

  test "redeem returns the user and consumes the code (dashes/case forgiven)" do
    code = @user.sign_in_codes.create!

    assert_equal @user, SignInCode.redeem(SignInCode.format(code.plaintext).downcase)
    assert code.reload.consumed_at.present?
  end

  test "a code cannot be redeemed twice" do
    code = @user.sign_in_codes.create!

    assert_equal @user, SignInCode.redeem(code.plaintext)
    assert_nil SignInCode.redeem(code.plaintext)
  end

  test "expired codes are not redeemable" do
    code = @user.sign_in_codes.create!
    code.update!(expires_at: 1.minute.ago)

    assert_nil SignInCode.redeem(code.plaintext)
  end

  test "malformed input is rejected without a query" do
    assert_nil SignInCode.redeem("not-a-code")
    assert_nil SignInCode.redeem("")
    assert_nil SignInCode.redeem(nil)
  end
end
