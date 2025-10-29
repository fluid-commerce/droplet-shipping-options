class ApplicationController < ActionController::Base
  include Pagy::Backend

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :log_session_info

protected

  def after_sign_in_path_for(resource)
    admin_dashboard_path
  end

  def current_ability
    @current_ability ||= Ability.new(user: current_user)
  end

private

  def log_session_info
    Rails.logger.info "Session ID: #{session.id}"
    Rails.logger.info "Session DRI: #{session[:dri]}"
    Rails.logger.info "Session keys: #{session.keys}"
  end
end
