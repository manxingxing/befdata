require 'test_helper'

class UserTest < ActiveSupport::TestCase
  # Replace this with your real tests.
  test "create user without login should not work" do
    user = User.new
    assert !user.save
  end

  test "add avatar to user" do
    @user = User.find_by_login 'nadrowski'
    @user.avatar = File.new(File.join(fixture_path,"test_files_for_uploads", "test-avatar.png"))

    assert @user.save!, "Avatar could not even be uploaded"

    expected_avatar_file_name = "#{@user.id}_#{@user.lastname}#{File.extname(@user.avatar.path).downcase}"
    error_hint = "Could not add avatar-image to user. Maybe Paperclip/ImageMagick is not correctly set up."
    assert @user.avatar_file_name == expected_avatar_file_name, error_hint
  end
end
