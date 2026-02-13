# frozen_string_literal: true

class Callbacks::CartCallbacksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :find_company

  # POST /callbacks/cart_customer_logged_in
  # User just logged in → check Exigo subscription → cache → recalculate shipping
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

      # Ask Core to recalculate shipping so UI reflects subscription status
      request_shipping_recalculate(cart_token) if cart_token.present?

      render json: { success: true, has_subscription: has_subscription }, status: :ok
    else
      render json: { success: true, message: "Subscription check skipped" }, status: :ok
    end
  end

  # POST /callbacks/verify_email_success
  # Fluid may call this after email verification. Same logic as update_email:
  # if the verified email differs from the cached login email, clear subscription cache.
  def email_verified
    update_email
  end

  # POST /callbacks/update_cart_email
  # Only clear subscription cache if email changes. We do NOT consult Exigo here.
  # Free shipping is only granted when user is authenticated (cart_customer_logged_in).
  # This prevents giving free shipping to anyone who types a subscriber's email.
  def update_email
    cart_id = payload[:cart][:id]
    new_cart_email = (params[:email] || params.dig(:cart, :email))&.to_s&.strip&.presence

    Rails.logger.info(
      "[CartCallback:update_email] cart_id=#{cart_id}, new_cart_email=#{new_cart_email.inspect}"
    )

    unless cart_id.present?
      return render json: { success: true, valid: true }, status: :ok
    end

    session = CartSessionService.new(cart_id)
    cached_email = session.cached_email

    # If email is blank or different from logged-in email, clear subscription state
    if new_cart_email.blank?
      Rails.logger.info("[CartCallback:update_email] Email blank, clearing cache")
      session.clear_all
    elsif cached_email.present? && new_cart_email.downcase != cached_email.downcase
      Rails.logger.info(
        "[CartCallback:update_email] Email changed from #{cached_email} to #{new_cart_email}, clearing cache"
      )
      session.clear_all
    else
      Rails.logger.info("[CartCallback:update_email] Email unchanged or no cached email, no action needed")
    end

    render json: { success: true, valid: true }, status: :ok
  end

private

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
