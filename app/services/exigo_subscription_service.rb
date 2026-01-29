# frozen_string_literal: true

class ExigoSubscriptionService
  def initialize(customer_id, company:)
    @customer_id = customer_id
    @company = company
    @base_url = company.exigo_api_url || ENV.fetch("EXIGO_API_URL", "https://sandboxapi4.exigo.com")
    @auth_token = company.exigo_auth_token || ENV.fetch("EXIGO_AUTH_TOKEN", "")
    @subscription_id = company.exigo_subscription_id || ENV.fetch("EXIGO_SUBSCRIPTION_ID", "9")
  end

  def has_active_subscription?
    return false unless @customer_id
    return false if @auth_token.blank?

    Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      check_subscription(@customer_id, @subscription_id)
    end
  end

  private

  def cache_key
    "exigo:subscription:#{@customer_id}:#{@subscription_id}"
  end

  def check_subscription(customer_id, subscription_id)
    response = HTTParty.get(
      "#{@base_url}/3.0/subscription",
      query: {
        subscriptionID: subscription_id,
        customerID: customer_id
      },
      headers: {
        "Authorization" => "Basic #{@auth_token}"
      },
      timeout: 3
    )

    if response.success?
      data = JSON.parse(response.body)

      # Si startDate es "0001-01-01" = NO tiene subscription
      start_date = data["startDate"]
      return false if start_date == "0001-01-01T00:00:00" || start_date.nil?

      # Verificar que no haya expirado
      expire_date = data["expireDate"]
      if expire_date.present? && expire_date != "0001-01-01T00:00:00"
        expire = DateTime.parse(expire_date)
        return false if expire < DateTime.now
      end

      # Tiene subscription activa
      has_subscription = true

      Rails.logger.info(
        "[ExigoSubscription] Customer #{customer_id} subscription #{subscription_id}: #{has_subscription} " \
        "(start: #{start_date}, expire: #{expire_date})"
      )

      has_subscription
    else
      Rails.logger.error(
        "[ExigoSubscription] API error #{response.code}: #{response.body}"
      )
      false
    end
  rescue StandardError => e
    Rails.logger.error(
      "[ExigoSubscription] Error for customer #{customer_id}: #{e.message}"
    )
    false
  end
end
