require "test_helper"

# Public sign-up is closed. AdminController admits any signed-in user, so an
# open /users/sign_up handed full admin to anyone who registered. Staff
# sign-in, sign-out and password reset must keep working.
class PublicSignupClosedTest < ActionDispatch::IntegrationTest
  SIGNUP_PARAMS = {
    user: {
      email: "outsider@example.com",
      password: "password123",
      password_confirmation: "password123",
    },
  }.freeze

  test "the sign-up page is not routed" do
    get "/users/sign_up"

    assert_response :not_found
  end

  test "posting a registration is not routed and creates no user" do
    assert_no_difference -> { User.count } do
      post "/users", params: SIGNUP_PARAMS
    end

    assert_response :not_found
    assert_nil User.find_by(email: "outsider@example.com")
  end

  test "the edit and cancel registration routes are gone" do
    get "/users/edit"
    assert_response :not_found

    get "/users/cancel"
    assert_response :not_found

    delete "/users"
    assert_response :not_found

    patch "/users"
    assert_response :not_found

    put "/users"
    assert_response :not_found
  end

  test "no registration route helpers are defined" do
    helpers = Rails.application.routes.url_helpers

    refute_respond_to helpers, :new_user_registration_path
    refute_respond_to helpers, :user_registration_path
    refute_respond_to helpers, :edit_user_registration_path
    refute_respond_to helpers, :cancel_user_registration_path
  end

  test "the User model does not include Devise registerable" do
    refute_includes User.devise_modules, :registerable
  end

  test "the sign-in page still renders" do
    get new_user_session_path

    assert_response :success
    assert_select "form[action=?]", user_session_path
  end

  test "the password reset page still renders" do
    get new_user_password_path

    assert_response :success
  end

  test "an existing user can still sign in, reach admin, and sign out" do
    Tasks::Settings.create_defaults
    User.create!(email: "staff@example.com", password: "password123", password_confirmation: "password123")

    post user_session_path, params: { user: { email: "staff@example.com", password: "password123" } }
    assert_redirected_to admin_dashboard_path

    get admin_dashboard_path
    assert_response :success

    delete destroy_user_session_path
    get admin_dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "a signed-in admin can still create a staff user, who can then sign in" do
    sign_in users(:admin)

    assert_difference -> { User.count }, 1 do
      post admin_users_path, params: {
        user: {
          email: "new-staff@example.com",
          password: "password123",
          password_confirmation: "password123",
          # The form's multi-select always submits a hidden "" alongside choices.
          permission_sets: [ "", "AdminPermissions" ],
        },
      }
    end
    assert_redirected_to admin_users_path

    sign_out :user
    post user_session_path, params: { user: { email: "new-staff@example.com", password: "password123" } }
    assert_redirected_to admin_dashboard_path
  end

  test "a signed-out visitor cannot create a user through the admin console" do
    assert_no_difference -> { User.count } do
      post admin_users_path, params: SIGNUP_PARAMS
    end

    assert_redirected_to new_user_session_path
  end

  test "a wrong password is still rejected" do
    User.create!(email: "staff@example.com", password: "password123", password_confirmation: "password123")

    post user_session_path, params: { user: { email: "staff@example.com", password: "wrong-password" } }

    assert_response :unprocessable_entity
    get admin_dashboard_path
    assert_redirected_to new_user_session_path
  end
end
