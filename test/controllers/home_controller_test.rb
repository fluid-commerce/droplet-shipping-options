require "test_helper"

describe HomeController do
  fixtures :companies

  it "redirects to shipping options when valid DRI session exists" do
    company = companies(:acme)
    get root_url, params: { dri: company.droplet_installation_uuid }
    must_respond_with :redirect
    must_redirect_to shipping_options_path
  end
end
