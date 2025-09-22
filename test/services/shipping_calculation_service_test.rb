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

  test "should return failure when no shipping options available" do
    # Crear un servicio con un país que no tiene shipping options
    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: "XX", # País inexistente
      ship_to_state: "YY",
      items: []
    )

    result = service.call

    assert_not result[:success]
    assert_equal "No shipping options available for this location", result[:error]
  end

  test "should calculate shipping total correctly with rate" do
    # Crear un rate específico
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
    # El fixture express_shipping tiene starting_rate de 15.99
    assert_equal 15.99, result[:shipping_options].first[:shipping_total]
  end

  test "should format delivery time correctly" do
    result = @service.call

    assert result[:success]
    shipping_option = result[:shipping_options].first

    # El fixture express_shipping tiene delivery_time de 2
    assert_equal "2 days", shipping_option[:shipping_delivery_time_estimate]
  end
end
