require "csv"

class RateCsvImportService
  attr_reader :company, :file, :errors, :success_count, :row_errors, :auto_correctable_errors

  def initialize(company:, file:)
    @company = company
    @file = file
    @errors = []
    @row_errors = []
    @auto_correctable_errors = []
    @success_count = 0
  end

  def call(apply_corrections: false)
    return failure("No file provided") unless file.present?
    return failure("Invalid file type. Please upload a CSV file.") unless valid_file_type?

    csv_data = read_csv_file
    return failure("Unable to read CSV file") unless csv_data

    validate_headers(csv_data)
    return failure("Invalid CSV headers") if errors.any?

    # If applying corrections, modify the CSV data first
    if apply_corrections
      csv_data = apply_auto_corrections(csv_data)
      # Clear row_errors since we've applied corrections
      @row_errors = []
    end

    import_rates(csv_data, apply_corrections: apply_corrections)

    # If applying corrections, only fail if there are non-correctable errors
    if apply_corrections
      non_correctable_errors = @row_errors.reject { |e| e[:auto_correctable] }
      if non_correctable_errors.any?
        failure("Import failed: #{non_correctable_errors.count} row(s) have errors that cannot be auto-corrected.")
      elsif @success_count > 0
        success
      else
        failure("No rates were imported")
      end
    elsif @row_errors.any?
      failure("Import failed: #{@row_errors.count} row(s) have errors. No records were imported.")
    elsif @success_count > 0
      success
    else
      failure("No rates were imported")
    end
  end

  def success?
    errors.empty? && row_errors.empty? && @success_count > 0
  end

private

  REQUIRED_HEADERS = %w[shipping_method country region min_range_lbs max_range_lbs flat_rate min_charge].freeze

  def valid_file_type?
    return false unless file.respond_to?(:path) || file.respond_to?(:read)

    # Check file extension first if available
    if file.respond_to?(:original_filename) && file.original_filename.present?
      return false unless File.extname(file.original_filename).downcase == ".csv"
    elsif file.respond_to?(:path)
      return false unless File.extname(file.path).downcase == ".csv"
    end

    # Then check content type if available
    if file.respond_to?(:content_type)
      file.content_type.in?([ "text/csv", "text/plain", "application/vnd.ms-excel" ])
    else
      true
    end
  end

  def read_csv_file
    content = file.respond_to?(:read) ? file.read : File.read(file.path)
    # Store original content for re-reading when applying corrections
    @csv_content = content
    CSV.parse(content, headers: true, header_converters: :symbol)
  rescue CSV::MalformedCSVError => e
    @errors << "Malformed CSV file: #{e.message}"
    nil
  rescue StandardError => e
    @errors << "Error reading CSV file: #{e.message}"
    nil
  end

  def validate_headers(csv_data)
    return if csv_data.headers.nil?

    missing_headers = REQUIRED_HEADERS.map(&:to_sym) - csv_data.headers
    if missing_headers.any?
      @errors << "Missing required columns: #{missing_headers.join(', ')}"
    end
  end

  def import_rates(csv_data, apply_corrections: false)
    # Pre-scan CSV to create missing shipping options
    ensure_shipping_options_exist(csv_data)

    # Preprocess and sort CSV data for proper import order
    sorted_data = preprocess_and_sort_csv(csv_data)

    # First pass: Validate all rows without saving
    validated_rates = []

    sorted_data.each do |row_data|
      row_number = row_data[:original_row_number]
      row = row_data[:row]

      begin
        rate, error = validate_rate_row(row, row_number, validated_rates, apply_corrections: apply_corrections)
        if error
          @row_errors << error
        elsif rate
          validated_rates << { rate: rate, row_number: row_number }
        end
      rescue StandardError => e
        @row_errors << { row: row_number, errors: [ e.message ], data: row.to_h }
      end
    end

    # If any errors, don't import anything
    # (When apply_corrections is true, auto-correctable errors are already fixed)
    # But we still need to check for non-correctable errors
    if @row_errors.any?
      Rails.logger.warn "[CSV Import] Found #{@row_errors.count} errors after validation"
      @row_errors.each do |error|
        Rails.logger.warn "[CSV Import] Row #{error[:row]}: #{error[:errors].join(', ')}"
      end
      return
    end

    # Second pass: All validations passed, save all records in a transaction
    ActiveRecord::Base.transaction do
      validated_rates.each do |item|
        item[:rate].save!
        @success_count += 1
      end
    end
  end

  # Apply auto-corrections to CSV data based on validation errors
  def apply_auto_corrections(csv_data)
    # First, validate to find all corrections needed
    corrections_map = {}

    csv_data.each_with_index do |row, index|
      next if row.to_h.values.all?(&:blank?)

      validation_result = validate_numeric_values(row, index + 2)
      if validation_result[:auto_correctable] && validation_result[:corrections].any?
        corrections_map[index] = validation_result[:corrections]
        Rails.logger.info "[CSV Import] Row #{index + 2} corrections: #{validation_result[:corrections].inspect}"
      end
    end

    # Apply corrections to the CSV data
    corrected_rows = []
    csv_data.each_with_index do |row, index|
      if corrections_map[index]
        corrected_row = row.to_h.dup
        corrections_map[index].each do |field, corrected_value|
          # Update the field value - ensure it's a string for CSV::Row
          corrected_row[field.to_sym] = corrected_value.to_s
          Rails.logger.info "[CSV Import] Row #{index + 2} corrected #{field}: " \
                            "#{row[field.to_sym]} -> #{corrected_value}"
        end
        # Convert back to CSV::Row maintaining header order
        row_values = csv_data.headers.map { |h| corrected_row[h.to_sym] }
        corrected_rows << CSV::Row.new(csv_data.headers, row_values)
      else
        corrected_rows << row
      end
    end

    # Create a new CSV table with corrected rows
    corrected_table = CSV::Table.new(corrected_rows)
    Rails.logger.info "[CSV Import] Applied corrections to #{corrections_map.size} row(s)"
    corrected_table
  end

  def validate_rate_row(row, row_number, validated_rates_in_batch = [], apply_corrections: false)
    # Skip empty rows
    return [ nil, nil ] if row.to_h.values.all?(&:blank?)

    shipping_option = find_shipping_option(row[:shipping_method], row_number)
    unless shipping_option
      return [ nil, {
        row: row_number,
        errors: [ "Shipping method '#{row[:shipping_method]&.strip}' not found" ],
        data: row.to_h,
      }, ]
    end

    region_value = row[:region]
    region_value = region_value.strip if region_value.is_a?(String)
    region_value = nil if region_value.blank?

    # Validate numeric values against database constraints before creating the rate
    # Skip validation if corrections were already applied (values should already be correct)
    unless apply_corrections
      validation_result = validate_numeric_values(row, row_number)
      if validation_result[:errors].any?
        return [ nil, {
          row: row_number,
          errors: validation_result[:errors],
          data: row.to_h,
          auto_correctable: validation_result[:auto_correctable],
          corrections: validation_result[:corrections],
        }, ]
      end
    end

    rate = shipping_option.rates.new(
      country: row[:country]&.strip&.upcase,
      region: region_value,
      min_range_lbs: BigDecimal(row[:min_range_lbs].to_s),
      max_range_lbs: BigDecimal(row[:max_range_lbs].to_s),
      flat_rate: BigDecimal(row[:flat_rate].to_s),
      min_charge: BigDecimal(row[:min_charge].to_s)
    )
    rate.skip_first_rate_validation = true

    # Validate against existing rates in database
    unless rate.valid?
      return [ nil, {
        row: row_number,
        data: row.to_h,
        errors: rate.errors.full_messages,
      }, ]
    end

    # Also validate against other rates in the same batch
    batch_errors = validate_against_batch(rate, validated_rates_in_batch)
    if batch_errors.any?
      return [ nil, {
        row: row_number,
        data: row.to_h,
        errors: batch_errors,
      }, ]
    end

    [ rate, nil ]
  end

  def validate_against_batch(rate, validated_rates_in_batch)
    errors = []
    country = rate.country
    region = rate.region

    # Find rates in the batch for the same location
    same_location_rates = validated_rates_in_batch.select do |item|
      item_rate = item[:rate]
      item_rate.country == country && item_rate.region == region
    end

    # Check if this is the first rate for this location (considering both database and batch)
    # The rate.valid? check already validates against the database, but we need to also check
    # against the batch. If there are no rates in the batch for this location AND no rates
    # in the database (which rate.valid? already checked), then this must be the first rate
    # and must start at 0.
    existing_db_rates = Rate.where(
      shipping_option: rate.shipping_option,
      country: country,
      region: region
    )
    if existing_db_rates.empty? && same_location_rates.empty? && rate.min_range_lbs != 0
      errors << "min_range_lbs must be 0 for the first rate of this shipping option and location"
    end

    # Check for overlapping ranges with rates in the batch
    same_location_rates.each do |item|
      other_rate = item[:rate]
      if ranges_overlap?(rate, other_rate)
        errors << "Weight range overlaps with existing rate " \
                  "(#{other_rate.min_range_lbs}-#{other_rate.max_range_lbs} lbs)"
        break
      end
    end

    errors
  end

  def ranges_overlap?(rate1, rate2)
    min1 = rate1.min_range_lbs || 0
    max1 = rate1.max_range_lbs || Float::INFINITY
    min2 = rate2.min_range_lbs || 0
    max2 = rate2.max_range_lbs || Float::INFINITY

    min1 < max2 && min2 < max1
  end

  def preprocess_and_sort_csv(csv_data)
    # Convert CSV rows to array with original row numbers for error reporting
    rows_with_numbers = []
    csv_data.each_with_index do |row, index|
      next if row.to_h.values.all?(&:blank?)

      rows_with_numbers << {
        row: row,
        original_row_number: index + 2, # +2 for 0-based index and header row
      }
    end

    # Sort by: shipping_method, country, region (nulls first), then min_range_lbs
    rows_with_numbers.sort_by do |row_data|
      row = row_data[:row]
      [
        row[:shipping_method]&.strip.to_s,
        row[:country]&.strip&.upcase.to_s,
        row[:region]&.strip.to_s == "" ? "" : row[:region]&.strip.to_s, # Empty strings sort before others
        row[:min_range_lbs].to_f,
      ]
    end
  end

  def ensure_shipping_options_exist(csv_data)
    # Group data by shipping method to calculate starting rates and countries
    shipping_methods_data = {}

    csv_data.each do |row|
      next if row.to_h.values.all?(&:blank?)

      method_name = row[:shipping_method]&.strip
      next if method_name.blank?

      shipping_methods_data[method_name] ||= {
        countries: Set.new,
        min_price: Float::INFINITY,
      }

      # Collect countries
      country = row[:country]&.strip&.upcase
      shipping_methods_data[method_name][:countries].add(country) if country.present?

      # Track minimum price
      flat_rate = row[:flat_rate].to_f
      if flat_rate > 0 && flat_rate < shipping_methods_data[method_name][:min_price]
        shipping_methods_data[method_name][:min_price] = flat_rate
      end
    end

    # Create or update shipping options
    shipping_methods_data.each do |method_name, data|
      min_price = data[:min_price] == Float::INFINITY ? 0 : data[:min_price]

      # Check if shipping option already exists
      existing_option = company.shipping_options.find_by(name: method_name)

      if existing_option
        # Update countries to include new ones from CSV
        updated_countries = (existing_option.countries + data[:countries].to_a).uniq
        existing_option.update!(
          countries: updated_countries,
          starting_rate: [ existing_option.starting_rate, min_price ].min
        )
      else
        # Create new shipping option
        company.shipping_options.create!(
          name: method_name,
          delivery_time: 5, # Default to 5 days
          starting_rate: min_price,
          countries: data[:countries].to_a,
          status: "active"
        )
      end
    end
  end

  def find_shipping_option(name, row_number)
    return nil if name.blank?

    company.shipping_options.find_by(name: name.strip)
  end

  # Validate numeric values against database constraints
  # min_range_lbs and max_range_lbs: precision 8, scale 4 (max: 9999.9999)
  # flat_rate and min_charge: precision 10, scale 2 (max: 99999999.99)
  # Returns hash with errors, auto_correctable flag, and corrections
  def validate_numeric_values(row, row_number)
    errors = []
    corrections = {}
    auto_correctable = false

    # Validate min_range_lbs and max_range_lbs (precision 8, scale 4)
    max_weight_value = BigDecimal("9999.9999")
    min_weight_value = BigDecimal("-9999.9999")

    min_range = BigDecimal(row[:min_range_lbs].to_s)
    if min_range > max_weight_value
      auto_correctable = true
      corrections[:min_range_lbs] = max_weight_value.to_s
      errors << "min_range_lbs (#{min_range}) exceeds maximum allowed value of 9999.9999 " \
                "(can be auto-corrected to #{max_weight_value})"
    elsif min_range < min_weight_value
      errors << "min_range_lbs (#{min_range}) is below minimum allowed value of #{min_weight_value}"
    end

    max_range = BigDecimal(row[:max_range_lbs].to_s)
    if max_range > max_weight_value
      auto_correctable = true
      corrections[:max_range_lbs] = max_weight_value.to_s
      errors << "max_range_lbs (#{max_range}) exceeds maximum allowed value of 9999.9999 " \
                "(can be auto-corrected to #{max_weight_value})"
    elsif max_range < min_weight_value
      errors << "max_range_lbs (#{max_range}) is below minimum allowed value of #{min_weight_value}"
    end

    # Validate flat_rate and min_charge (precision 10, scale 2)
    max_price_value = BigDecimal("99999999.99")
    min_price_value = BigDecimal("-99999999.99")

    flat_rate = BigDecimal(row[:flat_rate].to_s)
    if flat_rate > max_price_value
      auto_correctable = true
      corrections[:flat_rate] = max_price_value.to_s
      errors << "flat_rate (#{flat_rate}) exceeds maximum allowed value of 99999999.99 " \
                "(can be auto-corrected to #{max_price_value})"
    elsif flat_rate < min_price_value
      errors << "flat_rate (#{flat_rate}) is below minimum allowed value of #{min_price_value}"
    end

    min_charge = BigDecimal(row[:min_charge].to_s)
    if min_charge > max_price_value
      auto_correctable = true
      corrections[:min_charge] = max_price_value.to_s
      errors << "min_charge (#{min_charge}) exceeds maximum allowed value of 99999999.99 " \
                "(can be auto-corrected to #{max_price_value})"
    elsif min_charge < min_price_value
      errors << "min_charge (#{min_charge}) is below minimum allowed value of #{min_price_value}"
    end

    {
      errors: errors,
      auto_correctable: auto_correctable,
      corrections: corrections,
    }
  rescue ArgumentError, TypeError => e
    {
      errors: [ "Invalid numeric value: #{e.message}" ],
      auto_correctable: false,
      corrections: {},
    }
  end

  def success
    {
      success: true,
      message: "Successfully imported #{@success_count} rate(s)",
      imported_count: @success_count,
    }
  end

  def failure(message)
    @errors << message unless @errors.include?(message)
    {
      success: false,
      message: message,
      errors: @errors,
      row_errors: @row_errors,
      imported_count: 0,
    }
  end
end
