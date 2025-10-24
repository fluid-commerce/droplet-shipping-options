class ShippingOptionsController < ApplicationController
  include DriAuthentication

  layout "application"

  before_action :find_shipping_option, only: %i[edit update destroy disable]

  def index
    @shipping_options = @company.shipping_options.active
    @total_regions = @shipping_options.sum { |option| option.countries.count }
    @new_shipping_option = @company.shipping_options.build
  end

  def shipping_methods
    @new_shipping_option = @company.shipping_options.build
    @shipping_options = @company.shipping_options.all
  end

  def new
    @shipping_option = @company.shipping_options.build
  end

  def edit
    @shipping_option = @company.shipping_options.find(params[:id])
    Rails.logger.info "Edit shipping option: #{@shipping_option.inspect}"
    Rails.logger.info "Countries: #{@shipping_option.countries.inspect}"
  end

  def create
    @shipping_option = @company.shipping_options.build(shipping_option_params)

    if @shipping_option.save
      redirect_to shipping_methods_shipping_options_path, notice: "Shipping method was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @shipping_option.update(shipping_option_params)
      redirect_to shipping_methods_shipping_options_path, notice: "Shipping method was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @shipping_option.destroy
    redirect_to shipping_methods_shipping_options_path, notice: "Shipping method was successfully deleted."
  end

  def disable
    if @shipping_option.update(status: "inactive")
      if request.xhr?
        render json: { success: true, message: "Shipping method was successfully disabled." }
      else
        redirect_to shipping_methods_shipping_options_path, notice: "Shipping method was successfully disabled."
      end
    else
      if request.xhr?
        render json: { success: false, errors: @shipping_option.errors.full_messages }
      else
        redirect_to shipping_methods_shipping_options_path, alert: "Failed to disable shipping method."
      end
    end
  end

private

  def find_shipping_option
    @shipping_option = @company.shipping_options.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to shipping_methods_shipping_options_path, alert: "Shipping method not found."
  end

  def shipping_option_params
    permitted_params = params.require(:shipping_option).permit(
      :name, :delivery_time, :starting_rate, :status, countries: []
    )

    if permitted_params[:countries].is_a?(Array)
      permitted_params[:countries] = permitted_params[:countries].reject(&:blank?)
    end

    permitted_params
  end
end
