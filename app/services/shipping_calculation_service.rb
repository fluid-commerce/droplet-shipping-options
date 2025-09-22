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
      return failure_result("No shipping options available for this location")
    end

    success_result(shipping_options)
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
    state_rate = shipping_option.rates.find do |rate|
      rate.country_code == ship_to_country && rate.state_code == ship_to_state
    end

    country_rate = shipping_option.rates.find do |rate|
      rate.country_code == ship_to_country && rate.state_code.blank?
    end

    state_rate || country_rate
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
end
