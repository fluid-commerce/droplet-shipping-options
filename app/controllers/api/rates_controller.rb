module Api
  class RatesController < ApplicationController
    include DriAuthentication

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

      # Pagination
      total_count = rates.count
      limit = [ (params[:limit] || 1000).to_i, 2000 ].min
      offset = (params[:offset] || 0).to_i
      rates = rates.limit(limit).offset(offset)

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
        countries: countries,
        total_count: total_count,
        limit: limit,
        offset: offset,
      }
    end

    def bulk_update
      updates = params.require(:rates)

      errors = []
      updated_rates = []

      ActiveRecord::Base.transaction do
        updates.each do |update_params|
          rate = Rate.joins(:shipping_option)
                     .where(shipping_options: { company_id: @company.id })
                     .find_by(id: update_params[:id])

          unless rate
            errors << { id: update_params[:id], errors: [ "Rate not found or not accessible" ] }
            raise ActiveRecord::Rollback
          end

          permitted = update_params.permit(:flat_rate, :min_charge)

          # Type coercion for safety
          permitted[:flat_rate] = permitted[:flat_rate].to_f if permitted[:flat_rate].present?
          permitted[:min_charge] = permitted[:min_charge].to_f if permitted[:min_charge].present?

          unless rate.update(permitted)
            errors << { id: rate.id, errors: rate.errors.full_messages }
            raise ActiveRecord::Rollback
          end

          updated_rates << rate
        end
      end

      if errors.empty?
        render json: { success: true, updated_count: updated_rates.length }
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
        min_charge: rate.min_charge.to_f,
      }
    end
  end
end
