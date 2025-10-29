require "csv"

class RateCsvImportService
  attr_reader :company, :file, :errors, :success_count, :row_errors

  def initialize(company:, file:)
    @company = company
    @file = file
    @errors = []
    @row_errors = []
    @success_count = 0
  end

  def call
    return failure("No file provided") unless file.present?
    return failure("Invalid file type. Please upload a CSV file.") unless valid_file_type?

    csv_data = read_csv_file
    return failure("Unable to read CSV file") unless csv_data

    validate_headers(csv_data)
    return failure("Invalid CSV headers") if errors.any?

    import_rates(csv_data)

    if @success_count > 0 && row_errors.empty?
      success
    elsif @success_count > 0 && row_errors.any?
      partial_success
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

  def import_rates(csv_data)
    # Pre-scan CSV to create missing shipping options
    ensure_shipping_options_exist(csv_data)

    csv_data.each_with_index do |row, index|
      row_number = index + 2 # +2 because index is 0-based and we skip header row

      begin
        import_rate_row(row, row_number)
      rescue StandardError => e
        @row_errors << { row: row_number, errors: [ e.message ] }
      end
    end
  end

  def import_rate_row(row, row_number)
    # Skip empty rows
    return if row.to_h.values.all?(&:blank?)

    shipping_option = find_shipping_option(row[:shipping_method], row_number)
    return unless shipping_option

    region_value = row[:region]&.strip
    region_value = nil if region_value.blank?

    rate = shipping_option.rates.new(
      country: row[:country]&.strip&.upcase,
      region: region_value,
      min_range_lbs: row[:min_range_lbs],
      max_range_lbs: row[:max_range_lbs],
      flat_rate: row[:flat_rate],
      min_charge: row[:min_charge]
    )

    if rate.valid?
      rate.save!
      @success_count += 1
    else
      @row_errors << {
        row: row_number,
        data: row.to_h,
        errors: rate.errors.full_messages,
      }
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

    # Create missing shipping options
    shipping_methods_data.each do |method_name, data|
      next if company.shipping_options.exists?(name: method_name)

      min_price = data[:min_price] == Float::INFINITY ? 0 : data[:min_price]

      company.shipping_options.create!(
        name: method_name,
        delivery_time: 5, # Default to 5 days
        starting_rate: min_price,
        countries: data[:countries].to_a,
        status: "active"
      )
    end
  end

  def find_shipping_option(name, row_number)
    return nil if name.blank?

    shipping_option = company.shipping_options.find_by(name: name.strip)

    unless shipping_option
      @row_errors << {
        row: row_number,
        errors: [ "Shipping method '#{name}' not found" ],
      }
      return nil
    end

    shipping_option
  end

  def success
    {
      success: true,
      message: "Successfully imported #{@success_count} rate(s)",
      imported_count: @success_count,
    }
  end

  def partial_success
    {
      success: true,
      message: "Imported #{@success_count} rate(s) with #{row_errors.count} error(s)",
      imported_count: @success_count,
      row_errors: row_errors,
    }
  end

  def failure(message)
    @errors << message unless @errors.include?(message)
    {
      success: false,
      message: message,
      errors: @errors,
      row_errors: @row_errors,
    }
  end
end
