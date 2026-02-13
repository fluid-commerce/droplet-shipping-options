class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :validate_droplet_authorization, if: :droplet_installation_event?
  before_action :authenticate_webhook_token, unless: :droplet_installation_event?

  DROPLET_INSTALLATION_EVENTS = %w[installed uninstalled].freeze

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
      if EventHandler.route(event_type, payload, version: params[:version])
        { success: true, handled: true }
      else
        { success: true, handled: false }
      end
    end

    if result[:success]
      if result[:handled] == false
        head :no_content
      else
        head :accepted
      end
    else
      Rails.logger.error("[WebhooksController] Failed to process #{event_type}: #{result[:error]}")
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

private

  def droplet_installation_event?
    params[:resource] == "droplet" && DROPLET_INSTALLATION_EVENTS.include?(params[:event])
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
    return false if auth_header.blank?

    webhook_auth_token = Setting.fluid_webhook.auth_token
    company_token = company.webhook_verification_token

    # Accept either the global webhook token OR the company-specific verification token
    # Use secure_compare to prevent timing attacks
    ActiveSupport::SecurityUtils.secure_compare(auth_header.to_s, webhook_auth_token.to_s) ||
      (company_token.present? && ActiveSupport::SecurityUtils.secure_compare(auth_header.to_s, company_token.to_s))
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
