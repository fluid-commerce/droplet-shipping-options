require "test_helper"

class ShippingCalculationServiceTest < ActiveSupport::TestCase
  def setup
    @company = companies(:acme)
    @shipping_option = shipping_options(:express_shipping)
    @service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: []
    )
  end

  test "should return success with shipping options when valid" do
    result = @service.call

    assert result[:success]
    assert result[:shipping_options].is_a?(Array)
  end

  test "should return failure when company is missing" do
    service = ShippingCalculationService.new(
      company: nil,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: []
    )

    result = service.call

    assert_not result[:success]
    assert_equal "Invalid parameters", result[:error]
  end

  test "should return failure when country is missing" do
    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: nil,
      ship_to_state: "CA",
      items: []
    )

    result = service.call

    assert_not result[:success]
    assert_equal "Invalid parameters", result[:error]
  end

  test "should return failure when state is missing" do
    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: nil,
      items: []
    )

    result = service.call

    assert_not result[:success]
    assert_equal "Invalid parameters", result[:error]
  end

  test "should return default shipping response when no shipping options available" do
    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "XX",
      ship_to_state: "YY",
      items: []
    )

    result = service.call

    assert result[:success]
    assert_equal 1, result[:shipping_options].length
    assert_equal "Coordinate with the shop", result[:shipping_options].first[:shipping_title]
    assert_equal 0, result[:shipping_options].first[:shipping_total]
  end

  test "should calculate shipping total correctly with rate" do
    rate = @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 0,
      max_range_lbs: 100,
      flat_rate: 15.99,
      min_charge: 5.00
    )

    result = @service.call

    assert result[:success]
    assert_equal 15.99, result[:shipping_options].first[:shipping_total]
  end

  test "should use starting_rate when no specific rate exists" do
    result = @service.call

    assert result[:success]
    assert_equal 15.99, result[:shipping_options].first[:shipping_total]
  end

  test "should format delivery time correctly" do
    result = @service.call

    assert result[:success]
    shipping_option = result[:shipping_options].first

    assert_equal "2 days", shipping_option[:shipping_delivery_time_estimate]
  end

  # Tests for calculate_total_weight method
  test "should calculate total weight correctly with pounds" do
    items = [
      {
        id: 1,
        quantity: 2,
        variant: { weight: "5", unit_of_weight: "lb" },
      },
      {
        id: 2,
        quantity: 1,
        variant: { weight: "3", unit_of_weight: "lb" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: items
    )

    assert_equal 13.0, service.calculate_total_weight
  end

  test "should convert kg to pounds correctly" do
    items = [
      {
        id: 1,
        quantity: 1,
        variant: { weight: "1", unit_of_weight: "kg" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: items
    )

    assert_equal 2.20, service.calculate_total_weight
  end

  test "should convert grams to pounds correctly" do
    items = [
      {
        id: 1,
        quantity: 1,
        variant: { weight: "1000", unit_of_weight: "g" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: items
    )

    assert_equal 2.20, service.calculate_total_weight
  end

  test "should convert ounces to pounds correctly" do
    items = [
      {
        id: 1,
        quantity: 1,
        variant: { weight: "16", unit_of_weight: "oz" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: items
    )

    assert_equal 1.0, service.calculate_total_weight
  end

  test "should handle mixed units correctly" do
    items = [
      {
        id: 1,
        quantity: 1,
        variant: { weight: "1", unit_of_weight: "kg" },
      },
      {
        id: 2,
        quantity: 2,
        variant: { weight: "8", unit_of_weight: "oz" },
      },
      {
        id: 3,
        quantity: 1,
        variant: { weight: "500", unit_of_weight: "g" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: items
    )

    # 1kg = 2.20462 lbs, 16oz = 1 lb, 500g = 1.10231 lbs
    expected = 2.20462 + 1.0 + 1.10231
    assert_equal expected.round(2), service.calculate_total_weight
  end

  test "should return 0 when items are blank" do
    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: []
    )

    assert_equal 0.0, service.calculate_total_weight
  end

  test "should handle items without variant data" do
    items = [
      {
        id: 1,
        quantity: 1,
        variant: nil,
      },
      {
        id: 2,
        quantity: 1,
        variant: { weight: "5", unit_of_weight: "lb" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: items
    )

    assert_equal 5.0, service.calculate_total_weight
  end

  # Tests for rate_matches_weight_range? method
  test "should match rate when weight is within range" do
    rate = @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 15.99,
      min_charge: 5.00
    )

    items = [
      {
        id: 1,
        quantity: 1,
        variant: { weight: "5", unit_of_weight: "lb" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: items
    )

    assert service.send(:rate_matches_weight_range?, rate)
  end

  test "should not match rate when weight is below range" do
    # First create a rate with min_range_lbs: 0 (required by validation)
    @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 0,
      max_range_lbs: 5,
      flat_rate: 10.00,
      min_charge: 5.00
    )

    # Then create the rate we want to test
    rate = @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 10,
      max_range_lbs: 20,
      flat_rate: 15.99,
      min_charge: 5.00
    )

    items = [
      {
        id: 1,
        quantity: 1,
        variant: { weight: "5", unit_of_weight: "lb" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: items
    )

    assert_not service.send(:rate_matches_weight_range?, rate)
  end

  test "should not match rate when weight is above range" do
    rate = @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 0,
      max_range_lbs: 5,
      flat_rate: 15.99,
      min_charge: 5.00
    )

    items = [
      {
        id: 1,
        quantity: 1,
        variant: { weight: "10", unit_of_weight: "lb" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: items
    )

    assert_not service.send(:rate_matches_weight_range?, rate)
  end

  # Tests for rate_matches_location_exact? method
  test "should match rate when country and state match" do
    rate = @shipping_option.rates.create!(
      country: "US",
      region: "CA",
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

    assert service.send(:rate_matches_location_exact?, rate)
  end

  test "should not match rate when country does not match" do
    rate = @shipping_option.rates.create!(
      country: "CA",
      region: "CA",
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

    assert_not service.send(:rate_matches_location_exact?, rate)
  end

  test "should not match rate when state does not match" do
    rate = @shipping_option.rates.create!(
      country: "US",
      region: "NY",
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

    assert_not service.send(:rate_matches_location_exact?, rate)
  end

  # Integration test for find_best_rate with weight filtering
  test "should find best rate considering both location and weight" do
    # Create rates with different weight ranges
    rate1 = @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 0,
      max_range_lbs: 5,
      flat_rate: 10.00,
      min_charge: 5.00
    )

    rate2 = @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 5,
      max_range_lbs: 10,
      flat_rate: 15.00,
      min_charge: 10.00
    )

    # Items with weight 7 lbs (should match rate2)
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
      ship_to_state: "CA",
      items: items
    )

    best_rate = service.send(:find_best_rate, @shipping_option)
    assert_equal rate2.id, best_rate.id
    assert_equal 15.00, best_rate.flat_rate
  end

  test "should return nil when no rate matches location and weight" do
    # Create rate that doesn't match weight
    @shipping_option.rates.create!(
      country: "US",
      region: "CA",
      min_range_lbs: 0,
      max_range_lbs: 5,
      flat_rate: 10.00,
      min_charge: 5.00
    )

    # Items with weight 10 lbs (above max range)
    items = [
      {
        id: 1,
        quantity: 1,
        variant: { weight: "10", unit_of_weight: "lb" },
      },
    ]

    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "US",
      ship_to_state: "CA",
      items: items
    )

    best_rate = service.send(:find_best_rate, @shipping_option)
    assert_nil best_rate
  end
end
