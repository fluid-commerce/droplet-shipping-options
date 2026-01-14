# frozen_string_literal: true

# DriAuthentication
#
# Provides DRI (Droplet Installation UUID) management and validation for controllers.
# Handles session management, validation, and provides helpful error messages when
# DRIs are invalid or stale due to reinstallation.
module DriAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :store_dri_in_session
    before_action :find_company_by_dri
  end

private

  # Stores the DRI parameter in the session if provided.
  # If no DRI parameter is present but a DRI exists in session, it will be used.
  def store_dri_in_session
    dri = params[:dri]

    if dri.present?
      session[:dri] = dri
      Rails.logger.info "[DRI] Stored new DRI in session: #{dri}"
    elsif session[:dri].blank?
      Rails.logger.warn "[DRI] Missing DRI - params[:dri]: #{params[:dri].inspect}, " \
                        "session[:dri]: #{session[:dri].inspect}, session_id: #{session.id}, " \
                        "request_path: #{request.path}"
      render_dri_error(
        message: "DRI parameter is required",
        code: "DRI_REQUIRED",
        action_required: "Please access this page from the Fluid admin panel"
      )
    end
  end

  # Finds the company by DRI from the session.
  # Validates that:
  # 1. A DRI exists in the session
  # 2. A company exists with that DRI
  # 3. The company installation is active (not uninstalled)
  #
  # Provides helpful error messages for common failure scenarios.
  def find_company_by_dri
    dri = session[:dri]

    unless dri.present?
      return render_dri_error(
        message: "DRI parameter is required",
        code: "DRI_REQUIRED",
        action_required: "Please access this page from the Fluid admin panel"
      )
    end

    @company = Company.find_by(droplet_installation_uuid: dri)

    if @company.nil?
      handle_missing_company(dri)
    elsif @company.uninstalled?
      handle_uninstalled_company(dri)
    elsif !@company.active?
      handle_inactive_company(dri)
    end
  end

  # Handles the case where no company exists with the provided DRI.
  # This typically happens when:
  # 1. The droplet was uninstalled and reinstalled (new DRI created)
  # 2. The DRI is invalid or expired
  # 3. The user has a stale session
  def handle_missing_company(dri)
    Rails.logger.warn "[DRI] Company not found for DRI: #{dri}"

    # Try to find if a company exists that might have been reinstalled
    potential_company = find_potentially_reinstalled_company(dri)

    if potential_company
      handle_reinstalled_company(potential_company)
    else
      render_dri_error(
        message: "This droplet installation was removed or is invalid",
        code: "DRI_NOT_FOUND",
        action_required: "reinstall",
        details: "Please reinstall the droplet from the Fluid admin panel or contact support if this issue persists.",
        dri: dri
      )
    end
  end

  # Handles the case where the company exists but has been uninstalled
  def handle_uninstalled_company(dri)
    Rails.logger.warn "[DRI] Company found but marked as uninstalled: #{dri}"

    render_dri_error(
      message: "This droplet was uninstalled on #{@company.uninstalled_at.strftime('%B %d, %Y at %I:%M %p UTC')}",
      code: "DROPLET_UNINSTALLED",
      action_required: "reinstall",
      details: "Please reinstall the droplet from the Fluid admin panel to continue using it.",
      dri: dri
    )
  end

  # Handles the case where the company exists but is inactive
  def handle_inactive_company(dri)
    Rails.logger.warn "[DRI] Company found but marked as inactive: #{dri}"

    render_dri_error(
      message: "This droplet installation is inactive",
      code: "DROPLET_INACTIVE",
      action_required: "contact_support",
      details: "Please contact support for assistance.",
      dri: dri
    )
  end

  # Attempts to find a company that may have been reinstalled by looking for
  # the old DRI in their previous_dris history
  def find_potentially_reinstalled_company(old_dri)
    Rails.logger.info "[DRI] Checking for potential reinstallation related to: #{old_dri}"

    # Search for company where the old DRI exists in their previous_dris array
    company = Company.where("previous_dris @> ?", [old_dri].to_json).first

    if company
      Rails.logger.info "[DRI] Found reinstalled company #{company.fluid_shop} with current DRI: #{company.droplet_installation_uuid}"
    end

    company
  end

  # Handles the case where we detected a company was reinstalled
  # Clears the old session and provides instructions
  def handle_reinstalled_company(company)
    Rails.logger.info "[DRI] Found reinstalled company: #{company.id}, new DRI: #{company.droplet_installation_uuid}"

    # Clear the old DRI from session
    session.delete(:dri)

    render_dri_error(
      message: "This droplet was recently reinstalled with a new installation ID",
      code: "DROPLET_REINSTALLED",
      action_required: "refresh",
      details: "Please close this page and reopen the droplet from the Fluid admin panel.",
      suggested_dri: company.droplet_installation_uuid
    )
  end

  # Renders a JSON error response with helpful information
  def render_dri_error(message:, code:, action_required:, details: nil, dri: nil, suggested_dri: nil)
    error_response = {
      error: message,
      code: code,
      action_required: action_required,
    }

    error_response[:details] = details if details.present?
    error_response[:dri] = dri if dri.present?
    error_response[:suggested_dri] = suggested_dri if suggested_dri.present?

    render json: error_response, status: :not_found
  end
end
