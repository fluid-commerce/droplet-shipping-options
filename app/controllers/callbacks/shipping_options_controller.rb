class Callbacks::ShippingOptionsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :validate_payload
  before_action :find_company
  before_action :validate_shipping_location

  def create
    service = ShippingCalculationService.new(
      company: @company,
      ship_to_country: @ship_to_country,
      ship_to_state: @ship_to_state,
      items: payload[:cart][:items]
    )

    result = service.call

    if result[:success]
      render json: result, status: :ok
    else
      render json: result, status: :unprocessable_entity
    end
  end

private

  def validate_payload
    unless payload[:cart].present?
      render json: {
        success: false,
        error: "Cart data is required",
      }, status: :bad_request
      return
    end

    unless payload[:cart][:company].present?
      render json: {
        success: false,
        error: "Company data is required",
      }, status: :bad_request
      nil
    end
  end

  def find_company
    company_id = payload[:cart][:company][:id]

    @company = Company.find_by(fluid_company_id: company_id)

    unless @company
      render json: {
        success: false,
        error: "Company not found with ID: #{company_id}",
      }, status: :unauthorized
      nil
    end
  end

  def validate_shipping_location
    ship_to = payload[:cart][:ship_to]

    unless ship_to.present?
      render json: {
        success: false,
        error: "Shipping address is required",
      }, status: :bad_request
      return
    end

    @ship_to_country = ship_to[:country_code]
    @ship_to_state = ship_to[:state]

    unless @ship_to_country.present?
      render json: {
        success: false,
        error: "Country code is required",
      }, status: :bad_request
      return
    end

    unless @ship_to_state.present?
      render json: {
        success: false,
        error: "State/Province code is required",
      }, status: :bad_request
      nil
    end
  end

  def payload
    @payload ||= params.permit(
      cart: [
        :id,
        items: [
          :id,
          :name,
          :quantity,
          :price,
          variant: %i[id weight unit_of_weight unit_of_size],
        ],
        company: %i[id name],
        ship_to: %i[country_code state city zip address1 address2],
      ]
    ).to_h.deep_symbolize_keys
  end
end
