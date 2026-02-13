# frozen_string_literal: true

class ExigoSettingsController < ApplicationController
  include DriAuthentication

  before_action :ensure_yoli_company

  def edit; end

  def update
    @company.assign_attributes(settings_params)

    if @company.save
      redirect_to edit_exigo_setting_path(dri: params[:dri]),
                  notice: "Exigo settings updated successfully"
    else
      flash.now[:alert] = "Failed to update settings: #{@company.errors.full_messages.join(', ')}"
      render :edit
    end
  end

  def test_connection
    server = params[:server]
    database = params[:database]
    user = params[:user]
    password = params[:password]

    if server.blank? || database.blank? || user.blank? || password.blank?
      render json: { success: false, error: "All fields are required" }, status: :bad_request
      return
    end

    begin
      client = TinyTds::Client.new(
        host: server,
        database: database,
        username: user,
        password: password,
        timeout: 5,
        connect_timeout: 5
      )

      # Execute a simple query to verify the connection works
      result = client.execute("SELECT 1 AS test")
      result.each { |row| row }
      result.cancel

      client.close

      render json: {
        success: true,
        message: "Connection successful! Connected to #{database} on #{server}",
      }
    rescue TinyTds::Error => e
      render json: {
        success: false,
        error: "Database connection failed: #{e.message}",
      }, status: :unprocessable_entity
    rescue StandardError => e
      render json: {
        success: false,
        error: "Connection failed: #{e.message}",
      }, status: :unprocessable_entity
    end
  end

private

  def ensure_yoli_company
    unless @company&.yoli?
      redirect_to shipping_options_path(dri: params[:dri]),
                  alert: "Access denied: This feature is only available for Yoli"
    end
  end

  def settings_params
    {
      settings: {
        exigo_db_server: params.dig(:company, :exigo_db_server),
        exigo_db_name: params.dig(:company, :exigo_db_name),
        exigo_db_user: params.dig(:company, :exigo_db_user),
        exigo_db_password: params.dig(:company, :exigo_db_password),
        exigo_subscription_id: params.dig(:company, :exigo_subscription_id),
        free_shipping_for_subscribers: params.dig(:company, :free_shipping_for_subscribers) == "1",
      },
    }
  end
end
