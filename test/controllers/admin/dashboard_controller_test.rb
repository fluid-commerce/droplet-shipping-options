require "test_helper"

describe Admin::DashboardController do
  it "gets index" do
    Tasks::Settings.create_defaults

    sign_in users(:admin)
    get admin_dashboard_url
    must_respond_with :success
  end
end
