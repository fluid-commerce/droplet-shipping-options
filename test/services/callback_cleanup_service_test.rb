require "test_helper"

class CallbackCleanupServiceTest < ActiveSupport::TestCase
  test "recognizes us-south1 and legacy europe-west1 callback urls" do
    urls = CallbackCleanupService.own_callback_urls

    assert_includes urls, "https://fluid-droplet-shipping-options-295375388381.us-south1.run.app/callbacks/shipping_options"
    assert_includes urls, "https://fluid-droplet-shipping-options-106074092699.europe-west1.run.app/callbacks/shipping_options"
    assert_includes urls, "https://fluid-droplet-shipping-options-3h47nfle6q-ew.a.run.app/callbacks/shipping_options"
  end

  test "includes DROPLET_URL override alongside the defaults" do
    original = ENV["DROPLET_URL"]
    ENV["DROPLET_URL"] = "https://example.test"
    urls = CallbackCleanupService.own_callback_urls

    assert_includes urls, "https://example.test/callbacks/shipping_options"
    assert_includes urls, "https://fluid-droplet-shipping-options-106074092699.europe-west1.run.app/callbacks/shipping_options"
  ensure
    original.nil? ? ENV.delete("DROPLET_URL") : ENV["DROPLET_URL"] = original
  end
end
