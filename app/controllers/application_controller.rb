class ApplicationController < ActionController::Base
  include Pagy::Backend

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :log_session_info

  # Validates that droplet install/uninstall webhooks are for THIS droplet
  # This prevents cross-contamination from other droplets registered to the same owner company
  def validate_droplet_authorization
    expected_uuid = Setting.droplet.uuid
    received_uuid = params.dig(:company, :droplet_uuid)

    unless received_uuid.present? && expected_uuid.present? &&
           ActiveSupport::SecurityUtils.secure_compare(received_uuid.to_s, expected_uuid.to_s)
      Rails.logger.warn "[WebhookAuth] Rejected webhook for wrong droplet. Received: #{received_uuid}"
      render json: { error: "Unauthorized - wrong droplet" }, status: :unauthorized
    end
  end

protected

  def after_sign_in_path_for(resource)
    admin_dashboard_path
  end

  def current_ability
    @current_ability ||= Ability.new(user: current_user)
  end

  # Override redirect_to to automatically include DRI parameter when available
  # This ensures all redirects maintain the DRI parameter for iframe compatibility
  def redirect_to(options = {}, response_status = {})
    # Get DRI from session or params if available
    dri = session[:dri] || params[:dri]

    # If DRI is available, add it to the redirect options
    if dri.present?
      if options.is_a?(Hash)
        # For hash options (e.g., { controller: 'foo', action: 'bar' })
        options[:dri] ||= dri
      elsif options.is_a?(String)
        # For string URLs (including path helpers), append DRI parameter if not already present
        unless options.include?("dri=")
          separator = options.include?("?") ? "&" : "?"
          options = "#{options}#{separator}dri=#{CGI.escape(dri)}"
        end
      end
    end

    super(options, response_status)
  end

private

  def log_session_info
    Rails.logger.info "Session ID: #{session.id}"
    Rails.logger.info "Session DRI: #{session[:dri]}"
    Rails.logger.info "Session keys: #{session.keys}"
  end
end
