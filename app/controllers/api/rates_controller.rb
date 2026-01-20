module Api
  class RatesController < ApplicationController
    include DriAuthentication

    skip_before_action :verify_authenticity_token, only: [:bulk_update]
    before_action :set_csrf_cookie

    def index
      rates = Rate.joins(:shipping_option)
                  .where(shipping_options: { company_id: @company.id })
                  .includes(:shipping_option)
                  .order(:shipping_option_id, :country, :region, :min_range_lbs)

      # Apply filters
      if params[:shipping_option_id].present?
        rates = rates.where(shipping_option_id: params[:shipping_option_id])
      end

      if params[:country].present?
        rates = rates.where(country: params[:country])
      end

      shipping_options = @company.shipping_options
                                 .order(:name)
                                 .pluck(:id, :name)
                                 .map { |id, name| { id: id, name: name } }

      countries = Rate.joins(:shipping_option)
                      .where(shipping_options: { company_id: @company.id })
                      .distinct
                      .pluck(:country)
                      .compact
                      .sort

      render json: {
        rates: rates.map { |rate| serialize_rate(rate) },
        shipping_options: shipping_options,
        countries: countries
      }
    end

    def bulk_update
      updates = params.require(:rates)

      errors = []
      updated_ids = []

      ActiveRecord::Base.transaction do
        updates.each do |update_params|
          rate = Rate.joins(:shipping_option)
                     .where(shipping_options: { company_id: @company.id })
                     .find_by(id: update_params[:id])

          unless rate
            errors << { id: update_params[:id], errors: ["Rate not found"] }
            next
          end

          permitted = update_params.permit(:flat_rate, :min_charge)

          if rate.update(permitted)
            updated_ids << rate.id
          else
            errors << { id: rate.id, errors: rate.errors.full_messages }
          end
        end

        if errors.any?
          raise ActiveRecord::Rollback
        end
      end

      if errors.empty?
        render json: { success: true, updated_count: updated_ids.length }
      else
        render json: { success: false, errors: errors }, status: :unprocessable_entity
      end
    end

    private

    def serialize_rate(rate)
      {
        id: rate.id,
        shipping_option_id: rate.shipping_option_id,
        shipping_option_name: rate.shipping_option.name,
        country: rate.country,
        region: rate.region,
        min_range_lbs: rate.min_range_lbs.to_f,
        max_range_lbs: rate.max_range_lbs.to_f,
        flat_rate: rate.flat_rate.to_f,
        min_charge: rate.min_charge.to_f
      }
    end

    def set_csrf_cookie
      cookies["CSRF-TOKEN"] = form_authenticity_token
    end
  end
end
