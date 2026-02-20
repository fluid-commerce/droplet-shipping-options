class RatesController < ApplicationController
  include DriAuthentication

  layout "application"

  before_action :find_rate, only: %i[edit update destroy]

  def index
    @shipping_options = @company.shipping_options.includes(:rates)

    # Build query for all rates
    rates_query = Rate.joins(:shipping_option)
                      .where(shipping_options: { company_id: @company.id })
                      .includes(:shipping_option)
                      .order(created_at: :desc)

    # Apply filters with sanitized parameters
    filter_params = filter_rate_params

    if filter_params[:shipping_method].present?
      rates_query = rates_query.where(shipping_option_id: filter_params[:shipping_method])
    end

    if filter_params[:country].present?
      rates_query = rates_query.where(country: filter_params[:country])
    end

    if filter_params[:region].present?
      rates_query = rates_query.where(region: filter_params[:region])
    end

    if filter_params[:weight_min].present?
      rates_query = rates_query.where("min_range_lbs >= ?", filter_params[:weight_min])
    end

    if filter_params[:weight_max].present?
      rates_query = rates_query.where("max_range_lbs <= ?", filter_params[:weight_max])
    end

    # Paginate results with sanitized filter params
    @pagy, @rates = pagy(rates_query, limit: 20, params: filter_params)

    # Store sanitized filter params for the view
    @filter_params = filter_params

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

  def editor
    # React-based bulk editor
  end

  def process_import
    # If applying corrections, use stored file from temporary file
    if params[:apply_corrections] == "true"
      # Get file path from params (hidden field) or session
      # :brakeman:ignore FileAccess
      raw_file_path = params[:csv_import_file_path] || session[:csv_import_file_path]
      Rails.logger.info "[CSV Import] Applying corrections - file path: #{raw_file_path.inspect}"

      # Validate and sanitize file path to prevent directory traversal attacks
      # This validation ensures the path is safe before any file operations
      unless raw_file_path.present? && valid_temp_file_path?(raw_file_path)
        Rails.logger.warn "[CSV Import] Invalid or missing file path: #{raw_file_path.inspect}"
        redirect_to import_rate_tables_path, alert: "CSV file data expired. Please upload the file again."
        return
      end

      # Use validated path (sanitized and confirmed safe)
      temp_file_path = File.expand_path(raw_file_path, Rails.root.join("tmp"))

      if File.exist?(temp_file_path)
        # Read from temporary file - path has been validated and sanitized
        # :brakeman:ignore FileAccess
        # Path is validated by valid_temp_file_path? which ensures:
        # - Path is within tmp directory
        # - No directory traversal sequences (.., ~)
        # - Filename matches expected pattern (csv_import_*.csv)
        file_to_use = File.open(temp_file_path, "r")
        Rails.logger.info "[CSV Import] File found and opened"
        # Clean up after use
        session.delete(:csv_import_file_path)
      else
        Rails.logger.warn "[CSV Import] File not found at path: #{temp_file_path.inspect}"
        redirect_to import_rate_tables_path, alert: "CSV file data expired. Please upload the file again."
        return
      end
    elsif params[:csv_file].present?
      # Store file content in a temporary file for potential auto-correction
      file_to_use = params[:csv_file]
      if file_to_use.respond_to?(:read)
        csv_content = file_to_use.read
        file_to_use.rewind

        # Handle encoding: uploaded files may arrive as ASCII-8BIT with a
        # UTF-8 BOM (common when exported from Excel). Force to UTF-8 and
        # strip the BOM so downstream CSV parsing works cleanly.
        csv_content = csv_content.force_encoding("UTF-8")
        csv_content.delete_prefix!("\xEF\xBB\xBF")

        # Create a temporary file to store the CSV content
        temp_file = Tempfile.new([ "csv_import_#{session.id}_", ".csv" ], Rails.root.join("tmp"))
        temp_file.write(csv_content)
        temp_file.rewind
        temp_file_path = temp_file.path
        temp_file.close

        # Store the file path in session (much smaller than the file content)
        session[:csv_import_file_path] = temp_file_path
        Rails.logger.info "[CSV Import] Stored CSV in temporary file: #{temp_file_path}"

        # Reopen the file for the service to use
        file_to_use = File.open(temp_file_path, "r")
      end
    else
      redirect_to import_rate_tables_path, alert: "Please select a CSV file to upload."
      return
    end

    service = RateCsvImportService.new(
      company: @company,
      file: file_to_use
    )

    apply_corrections = params[:apply_corrections] == "true"
    result = service.call(apply_corrections: apply_corrections)

    if result[:success]
      # Clean up temporary file on success
      temp_file_path = session[:csv_import_file_path]
      if temp_file_path.present? && valid_temp_file_path?(temp_file_path) && File.exist?(temp_file_path)
        File.delete(temp_file_path) rescue nil
        session.delete(:csv_import_file_path)
      end
      flash[:notice] = result[:message]
      # Set Turbo-Frame header to break out of frame
      response.headers["Turbo-Frame"] = "_top"
      redirect_to rate_tables_path
    else
      # Check if ALL errors are auto-correctable
      all_auto_correctable = result[:row_errors].any? && result[:row_errors].all? { |e| e[:auto_correctable] }

      flash.now[:alert] = result[:message]
      flash.now[:errors] = result[:errors]
      flash.now[:row_errors] = result[:row_errors]
      flash.now[:has_auto_correctable] = result[:row_errors].any? { |e| e[:auto_correctable] }
      flash.now[:all_auto_correctable] = all_auto_correctable

      # Build correction summary for toast
      if all_auto_correctable
        correction_summary = build_correction_summary(result[:row_errors])
        flash.now[:correction_summary] = correction_summary
      end

      # Log session state to debug file path persistence
      Rails.logger.info "[CSV Import] Session file path after errors: #{session[:csv_import_file_path].inspect}"
      Rails.logger.info "[CSV Import] Session keys: #{session.keys.inspect}"

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

  def build_correction_summary(row_errors)
    summary = []
    row_errors.each do |error|
      next unless error[:auto_correctable]

      row_num = error[:row] || error[:row_number]
      corrections = error[:corrections] || {}

      corrections.each do |field, corrected_value|
        original_value = error[:data]&.dig(field.to_sym) || error[:data]&.dig(field.to_s) || "N/A"
        summary << {
          row: row_num,
          field: field,
          original: original_value,
          corrected: corrected_value,
        }
      end
    end
    summary
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

  def filter_rate_params
    result = {}
    result[:shipping_method] =
params[:shipping_method].to_i if params[:shipping_method].present? && params[:shipping_method].to_i > 0
    result[:country] = params[:country].to_s.strip if params[:country].present?
    result[:region] = params[:region].to_s.strip if params[:region].present?
    result[:weight_min] = params[:weight_min].to_f if params[:weight_min].present? && params[:weight_min].to_f > 0
    result[:weight_max] = params[:weight_max].to_f if params[:weight_max].present? && params[:weight_max].to_f > 0
    result
  end

  def valid_temp_file_path?(file_path)
    return false if file_path.blank?

    # Convert to absolute path and ensure it's within the tmp directory
    tmp_dir = Rails.root.join("tmp").to_s
    expanded_path = File.expand_path(file_path)

    # Check that the path is within the tmp directory
    return false unless expanded_path.start_with?(tmp_dir)

    # Check for directory traversal attempts
    return false if file_path.include?("..")
    return false if file_path.include?("~")

    # Validate filename pattern matches expected format (csv_import_*.csv)
    filename = File.basename(file_path)
    return false unless filename.match?(/\Acsv_import_.*\.csv\z/)

    true
  end
end
