# frozen_string_literal: true

class SubscriptionCheckService
  def initialize(email, company:)
    @email = email
    @company = company
  end

  def has_active_subscription?
    return false if @email.blank?

    threads = []
    threads << Thread.new { check_exigo }
    threads << Thread.new { check_fluid }

    # OR logic: either source returning true = subscriber
    threads.any? { |t| t.value }
  rescue StandardError => e
    Rails.logger.error("[SubscriptionCheck] Error: #{e.message}")
    false
  end

private

  def check_exigo
    ExigoSubscriptionService.new(@email, company: @company).has_active_subscription?
  rescue StandardError => e
    Rails.logger.error("[SubscriptionCheck] Exigo check failed: #{e.message}")
    false
  end

  def check_fluid
    FluidSubscriptionService.new(@email, company: @company).has_active_subscription?
  rescue StandardError => e
    Rails.logger.error("[SubscriptionCheck] Fluid check failed: #{e.message}")
    false
  end
end
