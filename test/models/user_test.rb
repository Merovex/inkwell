require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "with_email_address finds an existing user regardless of casing/whitespace" do
    assert_equal users(:alice), User.with_email_address("  ALICE@example.com ")
    assert_nil User.with_email_address("nobody@example.com")
  end

  test "send_magic_link creates one single-use code and enqueues one email" do
    alice = users(:alice)

    assert_difference -> { alice.sign_in_codes.count }, 1 do
      assert_enqueued_emails 1 do
        alice.send_magic_link(purpose: :sign_in)
      end
    end
  end

  test "display_name is the name, or the email address until one is set" do
    assert_equal "Alice Example", users(:alice).display_name

    users(:alice).update!(name: nil)
    assert_equal "alice@example.com", users(:alice).display_name
  end

  test "avatar rejects files over the size limit" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "huge.png", byte_size: User::AVATAR_MAX_SIZE + 1,
      checksum: "irrelevant", content_type: "image/png")
    blob.update!(identified: true) # skip identification — the blob has no real bytes

    # An unpersisted user defers the attach, so validation reads the blob's
    # metadata without ever touching (nonexistent) file bytes.
    user = User.new(email_address: "big@example.com")
    user.avatar.attach(blob)

    assert_not user.valid?
    assert_match(/smaller than 5 MB/, user.errors[:avatar].to_sentence)
  end

  test "registration policy reflects configuration" do
    assert_equal :invite_only, User.registration_policy
    assert_not User.registration_open?

    with_registration_policy :open do
      assert User.registration_open?
    end
  end
end
