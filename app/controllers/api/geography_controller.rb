module Api
  class GeographyController < ApplicationController
    include DriAuthentication

    COUNTRIES_CACHE_TTL = 6.hours
    STATES_CACHE_TTL = 6.hours

    def countries
      countries = Rails.cache.fetch("fluid_countries", expires_in: COUNTRIES_CACHE_TTL) do
        FluidClient.new.get("/api/countries")
      end

      render json: Array(countries).map { |c|
        { value: c["iso"], label: "#{c["name"]} (#{c["iso"]})" }
      }.sort_by { |c| c[:label] }
    rescue FluidClient::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout => e
      Rails.logger.error "[Geography] Failed to fetch countries: #{e.message}"
      render json: [], status: :ok
    end

    def states
      country_code = params[:country_code].to_s.strip.upcase
      return render(json: []) if country_code.blank?

      country_id = resolve_country_id(country_code)
      return render(json: []) if country_id.nil?

      states = Rails.cache.fetch("fluid_states_#{country_code}", expires_in: STATES_CACHE_TTL) do
        FluidClient.new.get("/api/states", query: { country_id: country_id })
      end

      render json: Array(states).map { |s|
        { value: s["name"], label: s["name"] }
      }
    rescue FluidClient::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout => e
      Rails.logger.error "[Geography] Failed to fetch states for #{country_code}: #{e.message}"
      render json: [], status: :ok
    end

  private

    def resolve_country_id(country_code)
      countries = Rails.cache.fetch("fluid_countries", expires_in: COUNTRIES_CACHE_TTL) do
        FluidClient.new.get("/api/countries")
      end

      country = Array(countries).find { |c| c["iso"] == country_code }
      country&.dig("id")
    end
  end
end
