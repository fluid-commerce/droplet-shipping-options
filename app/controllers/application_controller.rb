class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

protected

  def after_sign_in_path_for(resource)
    admin_dashboard_path
  end

  def current_ability
    @current_ability ||= Ability.new(user: current_user)
  end
end
