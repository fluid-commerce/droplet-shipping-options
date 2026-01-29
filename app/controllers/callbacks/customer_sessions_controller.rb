# frozen_string_literal: true

class Callbacks::CustomerSessionsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :validate_payload
  before_action :find_company

  # POST /callbacks/customer_sessions
  # Fluid ejecuta este callback cuando un usuario se loguea
  def create
    cart_id = payload[:cart][:id]
    user_id = payload[:user][:id]
    email = payload[:user][:email]

    # Guardar sesión del cart
    cart_session = CartSessionService.new(cart_id)
    cart_session.store_user_login(user_id, email: email)

    # Verificar si tiene suscripción activa en Exigo
    # Solo si la company es Yoli y tiene la feature habilitada
    if @company.yoli? && @company.free_shipping_enabled?
      has_subscription = ExigoSubscriptionService.new(user_id, company: @company).has_active_subscription?
      cart_session.store_subscription_status(has_subscription)

      render json: {
        success: true,
        message: "Session stored",
        has_subscription: has_subscription
      }, status: :ok
    else
      render json: {
        success: true,
        message: "Session stored (feature disabled)"
      }, status: :ok
    end
  end

  # POST /callbacks/customer_sessions/logout
  # Fluid ejecuta este callback cuando un usuario se desloguea
  def destroy
    cart_id = payload[:cart][:id]

    cart_session = CartSessionService.new(cart_id)
    cart_session.clear

    render json: { success: true, message: "Session cleared" }, status: :ok
  end

  private

  def validate_payload
    unless payload[:cart]&.dig(:id).present?
      render json: {
        success: false,
        error: "Cart ID is required"
      }, status: :bad_request
      return
    end

    unless payload[:user]&.dig(:id).present?
      render json: {
        success: false,
        error: "User ID is required"
      }, status: :bad_request
      return
    end
  end

  def find_company
    company_id = payload[:cart][:company][:id]

    @company = Company.find_by(fluid_company_id: company_id)

    unless @company
      render json: {
        success: false,
        error: "Company not found with ID: #{company_id}"
      }, status: :unauthorized
      return
    end
  end

  def payload
    @payload ||= params.permit(
      cart: [
        :id,
        company: [:id, :name]
      ],
      user: [:id, :email, :first_name, :last_name]
    ).to_h.deep_symbolize_keys
  end
end
