# frozen_string_literal: true

class ExigoSubscriptionService
  def initialize(email, company:)
    @email = email
    @company = company
    @subscription_id = company.exigo_subscription_id || "9"
  end

  def has_active_subscription?
    return false if @email.blank?
    return false unless db_configured?

    check_subscription_by_email
  rescue TinyTds::Error => e
    Rails.logger.error("[ExigoSubscription] DB error: #{e.message}")
    false
  rescue StandardError => e
    Rails.logger.error("[ExigoSubscription] Error: #{e.message}")
    false
  end

private

  def db_configured?
    @company.settings&.dig("exigo_db_server").present? &&
      @company.settings&.dig("exigo_db_name").present? &&
      @company.settings&.dig("exigo_db_user").present? &&
      @company.settings&.dig("exigo_db_password").present?
  end

  def check_subscription_by_email
    client = build_client
    result = client.execute(subscription_query)
    row = result.first
    result.cancel
    client.close

    has_subscription = row.present?

    Rails.logger.info(
      "[ExigoSubscription] Email=#{@email}, SubscriptionID=#{@subscription_id}: #{has_subscription}"
    )

    has_subscription
  end

  def subscription_query
    <<~SQL.squish
      SELECT TOP 1 cs.CustomerID
      FROM CustomerSubscriptions cs
      INNER JOIN Customers c ON cs.CustomerID = c.CustomerID
      WHERE cs.SubscriptionID = #{sanitize(@subscription_id)}
        AND cs.IsActive = 1
        AND c.Email = '#{sanitize_string(@email)}'
    SQL
  end

  def build_client
    TinyTds::Client.new(
      host: @company.settings["exigo_db_server"],
      database: @company.settings["exigo_db_name"],
      username: @company.settings["exigo_db_user"],
      password: @company.settings["exigo_db_password"],
      timeout: 5,
      connect_timeout: 5
    )
  end

  def sanitize(value)
    value.to_s.gsub(/[^0-9]/, "")
  end

  def sanitize_string(value)
    value.to_s.gsub("'", "''")
  end
end
