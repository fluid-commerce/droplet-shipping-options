# frozen_string_literal: true

class Callbacks::CartCallbacksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :find_company

  # POST /callbacks/cart_customer_logged_in
  def logged_in
    cart_id = payload[:cart][:id]
    cart_token = params.dig(:cart, :cart_token)
    email = params.dig(:cart, :email)&.to_s&.strip&.presence

    Rails.logger.info(
      "[CartCallback:logged_in] cart_id=#{cart_id}, email=#{email.inspect}"
    )

    unless cart_id.present?
      return render json: { success: false, error: "Cart ID is required" }, status: :bad_request
    end

    if @company.yoli? && @company.free_shipping_enabled? && email.present?
      has_subscription = ExigoSubscriptionService.new(email, company: @company).has_active_subscription?

      Rails.logger.info(
        "[CartCallback:logged_in] has_subscription=#{has_subscription}"
      )

      CartSessionService.new(cart_id).store_login(email, has_subscription: has_subscription)

      request_shipping_recalculate(cart_token) if cart_token.present?

      render json: { success: true, has_subscription: has_subscription }, status: :ok
    else
      render json: { success: true, message: "Subscription check skipped" }, status: :ok
    end
  end

  # POST /callbacks/verify_email_success
  def email_verified
    handle_email_change
  end

  # POST /callbacks/update_cart_email
  def update_email
    handle_email_change
  end

private

  def handle_email_change
    cart_id = payload[:cart][:id]
    new_cart_email = (params[:email] || params.dig(:cart, :email))&.to_s&.strip&.presence

    Rails.logger.info(
      "[CartCallback:handle_email_change] cart_id=#{cart_id}, new_cart_email=#{new_cart_email.inspect}"
    )

    if cart_id.present?
      session = CartSessionService.new(cart_id)
      cached_email = session.cached_email

      # If email is blank or different from logged-in email, clear subscription state
      if new_cart_email.blank? && cached_email.present?
        Rails.logger.info("[CartCallback] Email blank, clearing session")
        session.clear_all
      elsif cached_email.present? && new_cart_email.present? && new_cart_email.downcase != cached_email.downcase
        Rails.logger.info(
          "[CartCallback] Email changed from #{cached_email} to #{new_cart_email}, clearing session"
        )
        session.clear_all
      end
    end

    render json: { success: true, valid: true }, status: :ok
  end

  def find_company
    company_id = payload[:cart][:company][:id]

    @company = Company.find_by(fluid_company_id: company_id)

    unless @company
      render json: {
        success: false,
        error: "Company not found with ID: #{company_id}",
      }, status: :unauthorized
    end
  end

  def request_shipping_recalculate(cart_token)
    base_url = Setting.fluid_api.base_url
    token = @company.authentication_token

    Rails.logger.info(
      "[CartCallback] Requesting shipping recalculate " \
      "for cart_token=#{cart_token}"
    )

    HTTParty.post(
      "#{base_url}/api/carts/#{cart_token}/recalculate",
      headers: {
        "Authorization" => "Bearer #{token}",
        "Content-Type" => "application/json",
      }
    )
  rescue StandardError => e
    Rails.logger.error(
      "[CartCallback] Failed to recalculate: #{e.message}"
    )
  end

  def payload
    @payload ||= params.permit(
      :email,
      cart: [ :id, :email, :cart_token, company: %i[id name] ]
    ).to_h.deep_symbolize_keys
  end
end
