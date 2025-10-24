class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_webhook_token, unless: :droplet_installed_for_first_time?

  def create
    event_type = "#{params[:resource]}.#{params[:event]}"
    payload = params.to_unsafe_h.deep_dup

    result = case event_type
    when "droplet.installed"
      DropletInstallationService.new(payload).call
    when "droplet.uninstalled"
      DropletUninstallationService.new(payload).call
    else
      # Fall back to async job processing for other events
      EventHandler.route(event_type, payload, version: params[:version])
      { success: true }
    end

    if result[:success]
      head :accepted
    else
      Rails.logger.error("[WebhooksController] Failed to process #{event_type}: #{result[:error]}")
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

private

  def droplet_installed_for_first_time?
    params[:resource] == "droplet" && params[:event] == "installed"
  end

  def authenticate_webhook_token
    company = find_company
    if company.blank?
      render json: { error: "Company not found" }, status: :not_found
    elsif !valid_auth_token?(company)
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def valid_auth_token?(company)
    # Check header auth token first, then fall back to params
    auth_header = request.headers["AUTH_TOKEN"] || request.headers["X-Auth-Token"] || request.env["HTTP_AUTH_TOKEN"]
    webhook_auth_token = Setting.fluid_webhook.auth_token

    auth_header.present? && auth_header == webhook_auth_token
  end

  def find_company
    Company.find_by(droplet_installation_uuid: company_params[:droplet_installation_uuid]) ||
      Company.find_by(fluid_company_id: company_params[:fluid_company_id])
  end

  def company_params
    params.require(:company).permit(
      :company_droplet_uuid,
      :droplet_installation_uuid,
      :fluid_company_id,
      :webhook_verification_token,
      :authentication_token
    )
  end
end
