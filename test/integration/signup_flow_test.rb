require "test_helper"

# Signup is gated by a join code (root-only inviting by default); the code is
# multi-use and rotatable, and new users record who vouched for them.
class SignupFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @join_code = JoinCode.create!(user: users(:admin))
  end

  test "a valid code registers a member, records the inviter, and emails a link" do
    assert_difference "User.count", 1 do
      assert_enqueued_emails 1 do
        post signup_path, params: { signup: { email_address: "newcomer@example.com", invite_code: @join_code.code } }
      end
    end
    assert_redirected_to new_session_path(sent: true)

    newcomer = User.find_by(email_address: "newcomer@example.com")
    assert newcomer.member?
    assert_equal users(:admin), newcomer.inviter
  end

  test "code lookup is Crockford-normalized and grouping-tolerant" do
    formatted = @join_code.formatted.downcase.tr("1", "l")

    assert_difference "User.count", 1 do
      post signup_path, params: { signup: { email_address: "typed@example.com", invite_code: formatted } }
    end
    assert_redirected_to new_session_path(sent: true)
  end

  test "a missing or bogus code creates nothing" do
    assert_no_difference "User.count" do
      assert_no_enqueued_emails do
        post signup_path, params: { signup: { email_address: "newcomer@example.com", invite_code: "WRONGCODE" } }
        assert_response :unprocessable_entity

        post signup_path, params: { signup: { email_address: "newcomer@example.com", invite_code: "" } }
        assert_response :unprocessable_entity
      end
    end
  end

  test "a rotated code stops admitting; the fresh one works" do
    old_code = @join_code.code
    @join_code.rotate!

    assert_no_difference "User.count" do
      post signup_path, params: { signup: { email_address: "late@example.com", invite_code: old_code } }
      assert_response :unprocessable_entity
    end

    assert_difference "User.count", 1 do
      post signup_path, params: { signup: { email_address: "late@example.com", invite_code: @join_code.reload.code } }
    end
  end

  test "an already-registered address is reused without duplicating" do
    assert_no_difference "User.count" do
      assert_enqueued_emails 1 do
        post signup_path, params: { signup: { email_address: users(:bob).email_address, invite_code: @join_code.code } }
      end
    end
    assert_redirected_to new_session_path(sent: true)
  end

  test "a filled honeypot fakes success and persists nothing" do
    assert_no_difference "User.count" do
      assert_no_enqueued_emails do
        post signup_path, params: { signup: { email_address: "bot@example.com", invite_code: @join_code.code },
          InvisibleCaptcha.honeypots.first => "i am a bot" }
      end
    end
    assert_redirected_to new_session_path(sent: true)
  end

  test "sign-in's honeypot fakes the sent page without emailing" do
    assert_no_enqueued_emails do
      post session_path, params: { email_address: users(:bob).email_address,
        InvisibleCaptcha.honeypots.first => "i am a bot" }
    end
    assert_redirected_to new_session_path(sent: true)
  end
end
