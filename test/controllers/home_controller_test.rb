require "test_helper"

describe HomeController do
  fixtures :companies

  it "gets index" do
    company = companies(:acme)
    get root_url, params: { dri: company.droplet_installation_uuid }
    must_respond_with :success
  end
end
