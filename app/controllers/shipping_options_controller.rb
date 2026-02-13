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

  def sort_order
    @countries = @company.shipping_options.active.flat_map(&:countries).uniq.sort
    @selected_country = params[:country] || @countries.first
    @shipping_options = if @selected_country.present?
      @company.shipping_options
              .active
              .for_country(@selected_country)
              .ordered_for_country(@selected_country)
    else
      []
    end
  end

  def update_sort_order
    country_code = params[:country_code]
    positions = params[:positions] || []

    ActiveRecord::Base.transaction do
      positions.each do |pos|
        shipping_option = @company.shipping_options.find(pos[:id])
        shipping_option.set_position_for_country(country_code, pos[:position].to_i)
        shipping_option.save!
      end
    end

    respond_to do |format|
      format.json { render json: { success: true } }
      format.html { redirect_to sort_order_shipping_options_path(country: country_code), notice: "Sort order updated." }
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
      format.html do
        redirect_to sort_order_shipping_options_path(country: country_code),
                    alert: "Failed to update sort order."
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
      :name, :delivery_time, :starting_rate, :status, :free_for_subscribers, countries: []
    )

    if permitted_params[:countries].is_a?(Array)
      permitted_params[:countries] = permitted_params[:countries].reject(&:blank?)
    end

    permitted_params
  end
end
