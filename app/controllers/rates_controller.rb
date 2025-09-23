class RatesController < ApplicationController
  layout "application"

  before_action :store_dri_in_session
  before_action :find_company_by_dri
  before_action :find_shipping_option, only: %i[create]
  before_action :find_rate, only: %i[edit update destroy]

  def index
    @shipping_options = @company.shipping_options.includes(:rates)
  end

  def new
    @rate = @company.rates.build
    @shipping_methods = @company.shipping_options.pluck(:id, :name).map { |id, name| [ "#{name}", id ] }
  end

  def create
    shipping_option_id = rate_params[:shipping_option_id]

    if shipping_option_id.blank?
      @rate = @company.rates.build(rate_params)
      @rate.errors.add(:shipping_option_id, "can't be blank")
      @shipping_methods = @company.shipping_options.pluck(:id, :name).map { |id, name| [ "#{name}", id ] }
      render :new, status: :unprocessable_entity
      return
    end

    shipping_option = @company.shipping_options.find(shipping_option_id)
    @rate = shipping_option.rates.build(rate_params)

    if @rate.save
      redirect_to rate_tables_path, notice: "Rate was successfully created."
    else
      @shipping_methods = @company.shipping_options.pluck(:id, :name).map { |id, name| [ "#{name}", id ] }
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @shipping_methods = @company.shipping_options.pluck(:id, :name).map { |id, name| [ "#{name}", id ] }
  end

  def update
    if @rate.update(rate_params)
      redirect_to rate_tables_path, notice: "Rate was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rate.destroy
    redirect_to rate_tables_path, notice: "Rate was successfully deleted."
  end

private

  def store_dri_in_session
    dri = params[:dri]

    if dri.present?
      session[:dri] = dri
    elsif session[:dri].blank?
      render json: { error: "DRI parameter is required" }, status: :bad_request
    end
  end

  def find_company_by_dri
    dri = session[:dri]

    unless dri.present?
      render json: { error: "DRI parameter is required" }, status: :bad_request
    end

    @company = Company.find_by(droplet_installation_uuid: dri)

    unless @company
      render json: { error: "Company not found with DRI: #{dri}" }, status: :not_found
    end
  end

  def find_shipping_option
    shipping_option_id = params[:shipping_option_id] || params.dig(:rate, :shipping_option_id)
    @shipping_option = @company.shipping_options.find(shipping_option_id)
  rescue ActiveRecord::RecordNotFound
    redirect_to rate_tables_path, alert: "Shipping option not found."
  end

  def find_rate
    if @shipping_option
      @rate = @shipping_option.rates.find(params[:id])
    else
      @rate = Rate.joins(:shipping_option).where(shipping_options: { company_id: @company.id }).find(params[:id])
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to rate_tables_path, alert: "Rate not found."
  end

  def rate_params
    params.require(:rate).permit(
      :shipping_option_id, :country, :region, :min_range_lbs,
      :max_range_lbs, :flat_rate, :min_charge
    )
  end
end
