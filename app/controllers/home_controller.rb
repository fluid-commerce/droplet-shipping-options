class HomeController < ApplicationController
  include DriAuthentication

  def index
    # If we have a valid company/DRI session, redirect to shipping options
    if @company.present?
      redirect_to shipping_options_path
    end
    # Otherwise, show the landing page with the Fluid logo
  end
end
