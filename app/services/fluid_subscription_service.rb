# frozen_string_literal: true

class FluidSubscriptionService
  REQUEST_TIMEOUT = 5

  def initialize(email, company:)
    @email = email
    @company = company
    @product_id = company.fluid_subscription_product_id
  end

  def has_active_subscription?
    return false if @email.blank?
    return false if @product_id.blank?

    check_subscription_by_email
  rescue StandardError => e
    Rails.logger.error("[FluidSubscription] Error: #{e.message}")
    false
  end

private

  def check_subscription_by_email
    customer_id = find_customer_id
    return false unless customer_id

    orders = fetch_recent_orders(customer_id)
    return false if orders.blank?

    orders.any? { |order| order_contains_product?(order["id"]) }
  end

  def find_customer_id
    response = HTTParty.get(
      "#{base_url}/api/v2025-06/customers",
      query: { "filter[email]" => @email, "page[limit]" => 1 },
      headers: auth_headers,
      timeout: REQUEST_TIMEOUT
    )

    return nil unless response.code == 200

    customers = response.parsed_response&.dig("customers")
    customer = customers&.first
    return nil unless customer

    Rails.logger.info("[FluidSubscription] Found customer_id=#{customer['id']} for email=#{@email}")
    customer["id"]
  end

  def fetch_recent_orders(customer_id)
    start_date = 12.months.ago.strftime("%Y-%m-%d")

    response = HTTParty.get(
      "#{base_url}/api/v202506/orders",
      query: {
        customer_id: customer_id,
        sort: "-created_at",
        start_date: start_date,
      },
      headers: auth_headers,
      timeout: REQUEST_TIMEOUT
    )

    return [] unless response.code == 200

    orders = response.parsed_response&.dig("orders") || []
    Rails.logger.info("[FluidSubscription] Found #{orders.size} orders in last 12 months for id=#{customer_id}")
    orders
  end

  def order_contains_product?(order_id)
    return false unless order_id

    response = HTTParty.get(
      "#{base_url}/api/v202506/orders/#{order_id}",
      headers: auth_headers,
      timeout: REQUEST_TIMEOUT
    )

    return false unless response.code == 200

    items = response.parsed_response&.dig("order", "items") || []
    target_id = @product_id.to_i

    match = items.any? do |item|
      item_product_id = item.dig("variant", "product", "id") || item.dig("product", "id")
      item_product_id.to_i == target_id
    end

    Rails.logger.info("[FluidSubscription] Order #{order_id} contains product #{@product_id}: #{match}")
    match
  end

  def base_url
    Setting.fluid_api.base_url
  end

  def auth_headers
    {
      "Authorization" => "Bearer #{@company.authentication_token}",
      "Content-Type" => "application/json",
    }
  end
end
