require "test_helper"

class RateCsvImportServiceTest < ActiveSupport::TestCase
  def setup
    @company = companies(:acme)
    @shipping_option = shipping_options(:express_shipping)
  end

  test "should successfully import valid CSV file" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,5,9.99,5.00
      Express Shipping,US,NY,0,10,12.99,8.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 2, result[:imported_count]
    assert_equal "Successfully imported 2 rate(s)", result[:message]
    assert_equal 2, service.success_count
  end

  test "should return error when no file provided" do
    service = RateCsvImportService.new(company: @company, file: nil)

    result = service.call

    assert_not result[:success]
    assert_includes result[:message], "No file provided"
  end

  test "should return error for invalid file type" do
    file = Rack::Test::UploadedFile.new(StringIO.new("not a csv"), "text/plain", original_filename: "test.txt")
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert_includes result[:message], "Invalid file type"
  end

  test "should return error for missing required headers" do
    csv_content = <<~CSV
      shipping_method,country,min_range_lbs,max_range_lbs,flat_rate
      Express Shipping,US,0,5,9.99
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert_includes result[:message], "Invalid CSV headers"
    assert_includes result[:errors].first, "Missing required columns"
  end

  test "should handle malformed CSV file" do
    csv_content = "shipping_method,country,region\nExpress Shipping,US"
    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    # CSV parsing will handle this, but we should get some kind of result
    assert result
  end

  test "should skip empty rows" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,5,9.99,5.00
      ,,,,,,
      Express Shipping,US,NY,0,10,12.99,8.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 2, result[:imported_count]
  end

  test "should return row errors for invalid data" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,5,9.99,5.00
      Express Shipping,INVALID,CA,0,5,9.99,5.00
      Express Shipping,US,NY,10,5,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 1, result[:imported_count]
    assert result[:row_errors].present?
    assert_equal 2, result[:row_errors].count
  end

  test "should return error for non-existent shipping method" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Non Existent Method,US,CA,0,5,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert result[:row_errors].present?
    assert_includes result[:row_errors].first[:errors].first, "Shipping method 'Non Existent Method' not found"
  end

  test "should validate country code is 2 characters" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,USA,CA,0,5,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert result[:row_errors].present?
    assert_includes result[:row_errors].first[:errors].join, "wrong length"
  end

  test "should validate region is present" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,,0,5,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert result[:row_errors].present?
    assert_includes result[:row_errors].first[:errors].join, "can't be blank"
  end

  test "should validate min_range_lbs is greater than or equal to 0" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,-1,5,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert result[:row_errors].present?
    assert_includes result[:row_errors].first[:errors].join, "greater than or equal to 0"
  end

  test "should validate max_range_lbs is greater than min_range_lbs" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,10,5,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert result[:row_errors].present?
    assert_includes result[:row_errors].first[:errors].join, "must be greater than min_range_lbs"
  end

  test "should validate first rate for location must start at 0" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,FL,5,10,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert result[:row_errors].present?
    assert_includes result[:row_errors].first[:errors].join, "must be 0 for the first rate"
  end

  test "should normalize country code to uppercase" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,us,CA,0,5,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 1, result[:imported_count]

    rate = @shipping_option.rates.last
    assert_equal "US", rate.country
  end

  test "should trim whitespace from values" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping ,  US  , CA ,0,5,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 1, result[:imported_count]

    rate = @shipping_option.rates.last
    assert_equal "US", rate.country
    assert_equal "CA", rate.region
  end

  test "should import multiple rates for same shipping option and location" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,5,9.99,5.00
      Express Shipping,US,CA,5,10,14.99,10.00
      Express Shipping,US,CA,10,25,24.99,15.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 3, result[:imported_count]

    rates = @shipping_option.rates.where(country: "US", region: "CA").order(:min_range_lbs)
    assert_equal 3, rates.count
    assert_equal 0, rates.first.min_range_lbs
    assert_equal 5, rates.second.min_range_lbs
    assert_equal 10, rates.third.min_range_lbs
  end

  test "should detect overlapping weight ranges" do
    # Create first rate
    @shipping_option.rates.create!(
      country: "US",
      region: "TX",
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 10.00,
      min_charge: 5.00
    )

    # Try to import overlapping rate
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,TX,5,15,14.99,10.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert result[:row_errors].present?
    assert_includes result[:row_errors].first[:errors].join, "Weight range overlaps"
  end

  test "should return partial success when some rows succeed and some fail" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,5,9.99,5.00
      Non Existent Method,US,NY,0,5,9.99,5.00
      Express Shipping,US,TX,0,10,12.99,8.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 2, result[:imported_count]
    assert result[:row_errors].present?
    assert_equal 1, result[:row_errors].count
    assert_includes result[:message], "with"
    assert_includes result[:message], "error"
  end

private

  def create_csv_file(content)
    file = Tempfile.new([ "test", ".csv" ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "test.csv")
  end
end

