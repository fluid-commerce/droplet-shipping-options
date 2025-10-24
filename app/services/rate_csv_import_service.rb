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

    if file.respond_to?(:content_type)
      file.content_type.in?([ "text/csv", "text/plain", "application/vnd.ms-excel" ])
    elsif file.respond_to?(:path)
      File.extname(file.path).downcase == ".csv"
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

    rate = shipping_option.rates.new(
      country: row[:country]&.strip&.upcase,
      region: row[:region]&.strip,
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
      errors: row_errors,
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

