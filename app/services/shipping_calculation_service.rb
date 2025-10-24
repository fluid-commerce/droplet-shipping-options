class ShippingCalculationService
  include ActiveModel::Model
  include ActiveModel::Attributes

  attr_accessor :company
  attr_accessor :items
  attribute :ship_to_country, :string
  attribute :ship_to_state, :string

  validates :company, presence: true
  validates :ship_to_country, presence: true
  validates :ship_to_state, presence: true
  validates :items, presence: true, allow_blank: true

  def initialize(company:, ship_to_country:, ship_to_state:, items:)
    super(
      company: company,
      ship_to_country: ship_to_country,
      ship_to_state: ship_to_state,
      items: items
    )
  end

  def call
    return failure_result("Invalid parameters") unless valid?

    shipping_options = find_available_shipping_options

    if shipping_options.empty?
      return default_shipping_result
    end

    success_result(shipping_options)
  end

  def calculate_total_weight
    return 0.0 if items.blank?

    total_weight_in_lb = 0.0

    items.each do |item|
      next unless item[:variant] && item[:variant][:weight] && item[:quantity]

      weight = item[:variant][:weight].to_f
      quantity = item[:quantity].to_i
      unit_of_weight = item[:variant][:unit_of_weight]&.downcase

      weight_in_lb = convert_to_pounds(weight, unit_of_weight)

      total_weight_in_lb += (weight_in_lb * quantity)
    end

    total_weight_in_lb.round(2)
  end

private

  def find_available_shipping_options
    company.shipping_options
           .active
           .for_country(ship_to_country)
           .includes(:rates)
  end

  def success_result(shipping_options)
    {
      success: true,
      shipping_options: shipping_options.map { |option| serialize_shipping_option(option) },
    }
  end

  def default_shipping_result
    {
      success: true,
      shipping_options: [ default_shipping_response ],
    }
  end

  def failure_result(error_message)
    {
      success: false,
      error: error_message,
      shipping_options: [],
    }
  end

  def serialize_shipping_option(shipping_option)
    rate = find_best_rate(shipping_option)

    {
      shipping_total: calculate_shipping_total(shipping_option, rate),
      shipping_title: shipping_option.name,
      shipping_delivery_time_estimate: format_delivery_time(shipping_option.delivery_time),
    }
  end

  def find_best_rate(shipping_option)
    # First try to find region-specific rate
    region_rate = shipping_option.rates.find do |rate|
      rate_matches_location_exact?(rate) && rate_matches_weight_range?(rate)
    end
    return region_rate if region_rate

    # Fall back to country-level rate if no region-specific rate found
    shipping_option.rates.find do |rate|
      rate_matches_country_only?(rate) && rate_matches_weight_range?(rate)
    end
  end

  def calculate_shipping_total(shipping_option, rate)
    if rate
      [ rate.flat_rate, rate.min_charge ].max
    else
      shipping_option.starting_rate.to_f
    end
  end

  def format_delivery_time(delivery_time)
    case delivery_time
    when 0
      "Available same day"
    when 1
      "1 day"
    else
      "#{delivery_time} days"
    end
  end

  def default_shipping_response
    {
      shipping_total: 0,
      shipping_title: "Coordinate with the shop",
      shipping_delivery_time_estimate: 0,
    }
  end

private

  def rate_matches_location_exact?(rate)
    rate.country_code == ship_to_country &&
      rate.state_code.present? &&
      rate.state_code == ship_to_state
  end

  def rate_matches_country_only?(rate)
    rate.country_code == ship_to_country && rate.state_code.blank?
  end

  def rate_matches_weight_range?(rate)
    total_weight = calculate_total_weight
    total_weight >= rate.min_range_lbs && total_weight <= rate.max_range_lbs
  end

  def convert_to_pounds(weight, unit)
    case unit
    when "kg", "kgs", "kilogram", "kilograms"
      weight * 2.20462
    when "g", "gram", "grams"
      weight * 0.00220462
    when "oz", "ounce", "ounces"
      weight * 0.0625
    else
      weight
    end
  end
end
