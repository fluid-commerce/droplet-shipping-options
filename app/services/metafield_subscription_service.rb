# frozen_string_literal: true

class MetafieldSubscriptionService
  REQUEST_TIMEOUT = 5

  def initialize(email, company:)
    @email = email
    @company = company
  end

  def has_active_subscription?
    return false if @email.blank?
    return false if @company.blank?

    customer_id = find_customer_id
    return false unless customer_id

    check_subscription_metafield(customer_id)
  rescue StandardError => e
    Rails.logger.error("[MetafieldSubscription] Error: #{e.message}")
    false
  end

private

  def find_customer_id
    response = HTTParty.get(
      "#{base_url}/api/customers",
      query: { search_query: @email, per_page: 5 },
      headers: auth_headers,
      timeout: REQUEST_TIMEOUT
    )
    return nil unless response.code == 200

    customers = response.parsed_response&.dig("customers") || []
    customer = customers.find { |c| c["email"]&.downcase == @email.downcase }
    customer&.dig("id")
  end

  def check_subscription_metafield(customer_id)
    response = read_metafield(customer_id, "subscription_status")
    return false unless response.code == 200

    metafield = response.parsed_response&.dig("metafield")
    return false unless metafield
    return false unless metafield["value"] == true || metafield["value"] == "true"

    validate_subscription_date(customer_id)
  end

  def validate_subscription_date(customer_id)
    response = read_metafield(customer_id, "subscription_date")
    return true unless response.code == 200

    date_value = response.parsed_response&.dig("metafield", "value")
    return true if date_value.blank?

    Date.parse(date_value) > 12.months.ago.to_date
  rescue Date::Error
    true
  end

  def read_metafield(customer_id, key)
    HTTParty.get(
      "#{base_url}/api/v2/metafields/show",
      query: {
        resource_type: "customer",
        resource_id: customer_id,
        namespace: "yoli_plus",
        key: key,
      },
      headers: auth_headers,
      timeout: REQUEST_TIMEOUT
    )
  end

  def base_url
    Setting.fluid_api.base_url
  end

  def auth_headers
    {
      "Authorization" => "Bearer #{@company.authentication_token}",
      "Content-Type" => "application/json",
      "x-fluid-client" => "fluid-middleware",
    }
  end
end
