class RatesController < ApplicationController
  include DriAuthentication

  layout "application"

  before_action :find_shipping_option, only: %i[create]
  before_action :find_rate, only: %i[edit update destroy]

  def index
    @shipping_options = @company.shipping_options.includes(:rates)

    # Build query for all rates
    rates_query = Rate.joins(:shipping_option)
                      .where(shipping_options: { company_id: @company.id })
                      .includes(:shipping_option)
                      .order(created_at: :desc)

    # Apply filters
    if params[:shipping_method].present?
      rates_query = rates_query.where(shipping_option_id: params[:shipping_method])
    end

    if params[:country].present?
      rates_query = rates_query.where(country: params[:country])
    end

    if params[:region].present?
      rates_query = rates_query.where(region: params[:region])
    end

    if params[:weight_min].present?
      rates_query = rates_query.where("min_range_lbs >= ?", params[:weight_min])
    end

    if params[:weight_max].present?
      rates_query = rates_query.where("max_range_lbs <= ?", params[:weight_max])
    end

    # Paginate results
    @pagy, @rates = pagy(rates_query, limit: 20)

    # Get unique values for filter dropdowns
    @countries = Rate.joins(:shipping_option)
                     .where(shipping_options: { company_id: @company.id })
                     .distinct
                     .pluck(:country)
                     .compact
                     .sort

    @regions = Rate.joins(:shipping_option)
                   .where(shipping_options: { company_id: @company.id })
                   .where.not(region: nil)
                   .distinct
                   .pluck(:region)
                   .compact
                   .sort
  end

  def import
    # Show import form
  end

  def process_import
    unless params[:csv_file].present?
      redirect_to import_rate_tables_path, alert: "Please select a CSV file to upload."
      return
    end

    service = RateCsvImportService.new(
      company: @company,
      file: params[:csv_file]
    )

    result = service.call

    if result[:success]
      if result[:row_errors].present?
        flash[:warning] = result[:message]
        flash[:errors] = result[:row_errors]
      else
        flash[:notice] = result[:message]
      end
      redirect_to rate_tables_path
    else
      flash.now[:alert] = result[:message]
      flash.now[:errors] = result[:errors]
      flash.now[:row_errors] = result[:row_errors]
      render :import, status: :unprocessable_entity
    end
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
      @shipping_methods = @company.shipping_options.pluck(:id, :name).map { |id, name| [ "#{name}", id ] }
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rate.destroy
    redirect_to rate_tables_path, notice: "Rate was successfully deleted."
  end

private

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
