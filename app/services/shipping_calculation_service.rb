class ShippingCalculationService
  include ActiveModel::Model
  include ActiveModel::Attributes

  SHIPPING_OPTIONS_CACHE_TTL = 10.minutes

  attr_accessor :company
  attr_accessor :items
  attribute :ship_to_country, :string
  attribute :ship_to_state, :string

  validates :company, presence: true
  validates :ship_to_country, presence: true
  validates :ship_to_state, presence: true
  validates :items, presence: true, allow_blank: true

  def initialize(company:, ship_to_country:, ship_to_state:, items:, cart_id: nil, cart_email: nil)
    super(
      company: company,
      ship_to_country: ship_to_country,
      ship_to_state: ship_to_state,
      items: items
    )
    @cart_id = cart_id
    @cart_email = cart_email&.to_s&.strip&.presence
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
    @total_weight ||= compute_total_weight
  end

private

  def compute_total_weight
    return 0.0 if items.blank?

    total_weight_in_lb = 0.0

    Rails.logger.info "[ShippingCalc] Calculating total weight for #{items.size} items"

    items.each do |item|
      item_id = item[:id]
      variant_id = item[:variant]&.dig(:id)
      quantity = item[:quantity]
      weight = item[:variant]&.dig(:weight)
      unit = item[:variant]&.dig(:unit_of_weight)

      if item[:variant].nil?
        Rails.logger.warn "[ShippingCalc] Item #{item_id}: Skipped - no variant data"
        next
      end

      if weight.nil?
        Rails.logger.warn(
          "[ShippingCalc] Item #{item_id} (variant #{variant_id}), qty #{quantity}: Skipped - weight is nil"
        )
        next
      end

      unless quantity
        Rails.logger.warn "[ShippingCalc] Item #{item_id} (variant #{variant_id}): Skipped - no quantity"
        next
      end

      weight_value = weight.to_f
      quantity_value = quantity.to_i
      unit_of_weight = unit&.downcase

      weight_in_lb = convert_to_pounds(weight_value, unit_of_weight)
      item_total_weight = weight_in_lb * quantity_value

      Rails.logger.info(
        "[ShippingCalc] Item #{item_id} (variant #{variant_id}): " \
        "#{weight} #{unit || 'lb'} × #{quantity_value} = #{item_total_weight.round(2)} lbs"
      )

      total_weight_in_lb += item_total_weight
    end

    Rails.logger.info "[ShippingCalc] Total weight calculated: #{total_weight_in_lb.round(2)} lbs"

    total_weight_in_lb.round(2)
  end

  def find_available_shipping_options
    # Cache key excludes state intentionally - we cache shipping options per country,
    # then filter rates by state in Ruby (see find_best_rate). This allows sharing
    # cached options across all states within a country.
    cache_key = "shipping_opts:#{company.id}:#{ship_to_country}"

    base_options = Rails.cache.fetch(cache_key, expires_in: SHIPPING_OPTIONS_CACHE_TTL) do
      Rails.logger.info "[ShippingCalc] Cache miss for #{cache_key}, querying database"
      company.shipping_options
             .active
             .for_country(ship_to_country)
             .includes(:rates)
             .ordered_for_country(ship_to_country)
             .to_a  # Force load before caching
    end

    # Filter options based on subscription status (Yoli-specific feature)
    filter_by_subscription_status(base_options)
  end

  def success_result(shipping_options)
    {
      success: true,
      shipping_options: shipping_options.to_a.uniq(&:id).map { |option| serialize_shipping_option(option) },
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
    calculated_total = calculate_shipping_total(shipping_option, rate)

    # If this is a subscriber-only option and user has subscription, it's free
    final_total = if shipping_option.free_for_subscribers? && user_has_active_subscription?
                    0  # FREE!
                  else
                    calculated_total
                  end

    {
      shipping_total: final_total,
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

  # Yoli-specific: Filter shipping options based on subscription status
  def filter_by_subscription_status(shipping_options)
    return shipping_options unless company.yoli?

    has_subscription = user_has_active_subscription?

    shipping_options.select do |option|
      # If the method requires subscription, only include it if user has it
      if option.free_for_subscribers?
        if has_subscription
          Rails.logger.info(
            "[ShippingCalc] Including subscriber-only option: #{option.name}"
          )
          true
        else
          Rails.logger.info(
            "[ShippingCalc] Excluding subscriber-only option: #{option.name} " \
            "(user not subscribed)"
          )
          false
        end
      else
        # Normal options always included
        true
      end
    end
  end

  # Yoli-specific: Only read subscription state from cache. We never change state here.
  # State is set only by update_cart_email and cart_customer_logged_in (they check Exigo and store).
  # IMPORTANT: We verify that the cart email matches the cached email to prevent stale subscription state.
  def user_has_active_subscription?
    return false unless @cart_id
    return false unless company.yoli?
    return false unless company.free_shipping_enabled?

    session = CartSessionService.new(@cart_id)
    cached_email = session.cached_email
    cached_subscription = session.has_active_subscription?

    Rails.logger.info(
      "[ShippingCalc] Subscription check: cart_id=#{@cart_id}, " \
      "cart_email=#{@cart_email.inspect}, cached_email=#{cached_email.inspect}, " \
      "cached_subscription=#{cached_subscription}"
    )

    # If no cached email, user is not logged in - no free shipping
    unless cached_email.present?
      Rails.logger.info("[ShippingCalc] No cached email, returning false")
      return false
    end

    # If cart email doesn't match cached email, subscription state is stale - ignore it
    if @cart_email.present? && @cart_email.downcase != cached_email.downcase
      Rails.logger.info(
        "[ShippingCalc] Email mismatch: cart_email=#{@cart_email}, cached_email=#{cached_email}. " \
        "Ignoring cached subscription state."
      )
      return false
    end

    Rails.logger.info("[ShippingCalc] Returning cached subscription: #{cached_subscription}")
    cached_subscription
  end
end
