require "test_helper"

class DriAuthenticationTest < ActionDispatch::IntegrationTest
  fixtures :companies

  setup do
    @company = companies(:acme)
    @valid_dri = @company.droplet_installation_uuid
  end

  test "accessing with valid DRI stores it in session" do
    get root_path, params: { dri: @valid_dri }
    assert_response :redirect
    expected_url = shipping_options_url(dri: @valid_dri)
    assert_equal expected_url, response.location
    assert_equal @valid_dri, session[:dri]
  end

  test "accessing with invalid DRI returns error" do
    get shipping_options_path, params: { dri: "dri_invalid123" }
    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal "DRI_NOT_FOUND", json_response["code"]
    assert_equal "reinstall", json_response["action_required"]
  end

  test "accessing with uninstalled company DRI returns error" do
    @company.update(uninstalled_at: Time.current)
    get shipping_options_path, params: { dri: @valid_dri }
    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal "DROPLET_UNINSTALLED", json_response["code"]
  end

  test "accessing with inactive company DRI returns error" do
    @company.update(active: false, uninstalled_at: nil)
    get shipping_options_path, params: { dri: @valid_dri }
    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal "DROPLET_INACTIVE", json_response["code"]
  end

  test "accessing without DRI when session has valid DRI works" do
    # First request with DRI to set session
    get root_path, params: { dri: @valid_dri }
    assert_response :redirect
    expected_url = shipping_options_url(dri: @valid_dri)
    assert_equal expected_url, response.location

    # Second request without DRI should use session
    get shipping_options_path
    assert_response :success
  end

  test "accessing without DRI and no session returns error" do
    get shipping_options_path
    assert_response :not_found
    json_response = JSON.parse(response.body)
    assert_equal "DRI_REQUIRED", json_response["code"]
  end
end
