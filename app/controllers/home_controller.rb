class HomeController < ApplicationController
  include DriAuthentication

  def index
    # If we have a valid company/DRI session, redirect to shipping options
    if @company.present?
      # Include DRI in redirect URL as fallback in case cookies aren't working in iframe
      dri = session[:dri] || params[:dri]
      redirect_to shipping_options_path(dri: dri)
    end
    # Otherwise, show the landing page with the Fluid logo
  end
end
