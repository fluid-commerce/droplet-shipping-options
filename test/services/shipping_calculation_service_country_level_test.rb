require "test_helper"

class ShippingCalculationServiceCountryLevelTest < ActiveSupport::TestCase
  def setup
    @company = companies(:acme)
    @shipping_option = shipping_options(:express_shipping)
  end

  test "should match country-level rate when no region-specific rate exists" do
    # Create only country-level rate (no region)
    country_rate = @shipping_option.rates.create!(
      country: "US",
      region: nil,
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 15.99,
      min_charge: 5.00
    )

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: []
    )

    result = service.call

    assert result[:success]
    assert result[:shipping_options].length >= 1
    # Find the specific shipping option we're testing
    express_option = result[:shipping_options].find { |opt| opt[:shipping_title] == "Express Shipping" }
    assert_not_nil express_option
    assert_equal 15.99, express_option[:shipping_total]
  end

  test "should prefer region-specific rate over country-level rate" do
    # Create country-level rate
    @shipping_option.rates.create!(
      country: "US",
      region: nil,
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 10.00,
      min_charge: 5.00
    )

    # Create region-specific rate (should be preferred)
    @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 15.99,
      min_charge: 8.00
    )

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: []
    )

    result = service.call

    assert result[:success]
    assert result[:shipping_options].length >= 1
    # Find the specific shipping option we're testing
    express_option = result[:shipping_options].find { |opt| opt[:shipping_title] == "Express Shipping" }
    assert_not_nil express_option
    # Should use the region-specific rate, not country-level
    assert_equal 15.99, express_option[:shipping_total]
  end

  test "should fall back to country-level rate when region-specific rate doesn't exist" do
    # Create region-specific rate for NY
    @shipping_option.rates.create!(
      country: "US",
      region: "NY",
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 20.00,
      min_charge: 10.00
    )

    # Create country-level rate
    @shipping_option.rates.create!(
      country: "US",
      region: nil,
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 12.99,
      min_charge: 7.00
    )

    # Request for CA (no CA-specific rate, should use country-level)
    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: []
    )

    result = service.call

    assert result[:success]
    assert result[:shipping_options].length >= 1
    # Find the specific shipping option we're testing
    express_option = result[:shipping_options].find { |opt| opt[:shipping_title] == "Express Shipping" }
    assert_not_nil express_option
    # Should use country-level rate since CA doesn't have region-specific rate
    assert_equal 12.99, express_option[:shipping_total]
  end

  test "should handle multiple weight ranges with country-level rates" do
    # Create country-level rates with different weight ranges
    @shipping_option.rates.create!(
      country: "US",
      region: nil,
      min_range_lbs: 0,
      max_range_lbs: 5,
      flat_rate: 8.99,
      min_charge: 5.00
    )

    @shipping_option.rates.create!(
      country: "US",
      region: nil,
      min_range_lbs: 5,
      max_range_lbs: 15,
      flat_rate: 14.99,
      min_charge: 10.00
    )

    items = [
      {
        id: 1,
        quantity: 1,
        variant: { weight: "7", unit_of_weight: "lb" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "TX",
      items: items
    )

    result = service.call

    assert result[:success]
    # Should match the 5-15 lbs range
    express_option = result[:shipping_options].find { |opt| opt[:shipping_title] == "Express Shipping" }
    assert_not_nil express_option
    assert_equal 14.99, express_option[:shipping_total]
  end

  test "should exclude shipping option when neither region-specific nor country-level rate matches" do
    # Create rate for different country
    @shipping_option.rates.create!(
      country: "CA",
      region: nil,
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 15.99,
      min_charge: 10.00
    )

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: []
    )

    result = service.call

    assert result[:success]
    # Should not include shipping option since no matching rate for US
    express_option = result[:shipping_options].find { |opt| opt[:shipping_title] == "Express Shipping" }
    assert_nil express_option
  end

  test "rate_matches_location_exact should only match when region is present and matches" do
    country_level_rate = @shipping_option.rates.create!(
      country: "US",
      region: nil,
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 10.00,
      min_charge: 5.00
    )

    region_rate = @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 15.00,
      min_charge: 8.00
    )

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: []
    )

    assert_not service.send(:rate_matches_location_exact?, country_level_rate)
    assert service.send(:rate_matches_location_exact?, region_rate)
  end

  test "rate_matches_country_only should only match when region is blank" do
    country_level_rate = @shipping_option.rates.create!(
      country: "US",
      region: nil,
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 10.00,
      min_charge: 5.00
    )

    region_rate = @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 15.00,
      min_charge: 8.00
    )

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: []
    )

    assert service.send(:rate_matches_country_only?, country_level_rate)
    assert_not service.send(:rate_matches_country_only?, region_rate)
  end
end
