require "test_helper"

class RatesControllerTest < ActionDispatch::IntegrationTest
  fixtures :companies

  test "gets index with dri parameter" do
    get rate_tables_url, params: { dri: "test-dri" }
    assert_response :success
  end

  test "gets new with dri parameter" do
    get new_rate_table_url, params: { dri: "test-dri" }
    # Puede ser success o redirect, pero no debe ser 400 Bad Request
    assert_not_equal 400, response.status
  end

  test "gets create with dri parameter" do
    post rate_tables_url, params: { dri: "test-dri", rate: { country: "" } }
    # Puede ser success o redirect, pero no debe ser 400 Bad Request
    assert_not_equal 400, response.status
  end

  test "gets edit with dri parameter" do
    get edit_rate_table_url(id: 1), params: { dri: "test-dri" }
    # Puede ser success o redirect, pero no debe ser 400 Bad Request
    assert_not_equal 400, response.status
  end

  test "gets update with dri parameter" do
    patch rate_table_url(id: 1), params: { dri: "test-dri" }
    # Puede ser success o redirect, pero no debe ser 400 Bad Request
    assert_not_equal 400, response.status
  end

  test "gets destroy with dri parameter" do
    delete rate_table_url(id: 1), params: { dri: "test-dri" }
    # Puede ser success o redirect, pero no debe ser 400 Bad Request
    assert_not_equal 400, response.status
  end
end
