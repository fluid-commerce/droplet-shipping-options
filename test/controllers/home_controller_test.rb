require "test_helper"

describe HomeController do
  fixtures :companies

  it "redirects to shipping options when valid DRI session exists" do
    company = companies(:acme)
    get root_url, params: { dri: company.droplet_installation_uuid }
    must_respond_with :redirect
    expected_url = shipping_options_url(dri: company.droplet_installation_uuid)
    assert_equal expected_url, response.location
  end
end
