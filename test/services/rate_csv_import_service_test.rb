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

  test "should return row errors for invalid data and not import anything" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,5,9.99,5.00
      Express Shipping,INVALID,CA,0,5,9.99,5.00
      Express Shipping,US,NY,10,5,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert_equal 0, result[:imported_count]
    assert result[:row_errors].present?
    assert_equal 2, result[:row_errors].count
  end

  test "should auto-create non-existent shipping method" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      New Method,US,CA,0,5,9.99,5.00
      New Method,CA,,0,10,15.99,10.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    initial_count = @company.shipping_options.count

    result = service.call

    assert result[:success]
    assert_equal 2, result[:imported_count]

    # Verify shipping method was created
    new_method = @company.shipping_options.find_by(name: "New Method")
    assert_not_nil new_method
    assert_equal 5, new_method.delivery_time
    assert_equal 9.99, new_method.starting_rate
    assert_equal %w[CA US], new_method.countries.sort
    assert_equal "active", new_method.status
    assert_equal initial_count + 1, @company.shipping_options.count
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

  test "should allow blank region for country-level rates" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,,0,5,9.99,5.00
      Express Shipping,US,,5,10,14.99,10.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 2, result[:imported_count]

    rates = @shipping_option.rates.where(country: "US", region: [ nil, "" ]).order(:min_range_lbs)
    assert_equal 2, rates.count
    assert_nil rates.first.region
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

  test "should replace existing rates instead of failing on overlap with existing DB rates" do
    # Create first rate
    @shipping_option.rates.create!(
      country: "US",
      region: "TX",
      min_range_lbs: 0,
      max_range_lbs: 10,
      flat_rate: 10.00,
      min_charge: 5.00
    )

    # Import a rate for the same location — with upsert, existing rates are
    # replaced so overlaps with DB records no longer cause failures.
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,TX,0,15,14.99,10.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 1, result[:imported_count]
    assert_equal 1, result[:replaced_count]

    tx_rates = @shipping_option.rates.where(country: "US", region: "TX")
    assert_equal 1, tx_rates.count
    assert_equal 14.99, tx_rates.first.flat_rate
  end

  test "should detect overlapping weight ranges within the same CSV batch" do
    # Overlapping ranges within the CSV itself should still fail
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,TX,0,10,9.99,5.00
      Express Shipping,US,TX,5,15,14.99,10.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert result[:row_errors].present?
    assert_includes result[:row_errors].first[:errors].join, "Weight range overlaps"
  end

  test "should auto-create multiple new shipping methods" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      New Method A,US,CA,0,5,12.99,8.00
      New Method B,CA,,0,10,8.99,5.00
      New Method A,MX,,0,8,15.99,10.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    initial_count = @company.shipping_options.count

    result = service.call

    assert result[:success]
    assert_equal 3, result[:imported_count]
    assert_equal initial_count + 2, @company.shipping_options.count

    # Verify New Method A
    method_a = @company.shipping_options.find_by(name: "New Method A")
    assert_not_nil method_a
    assert_equal 5, method_a.delivery_time
    assert_equal 12.99, method_a.starting_rate
    assert_equal %w[MX US], method_a.countries.sort
    assert_equal "active", method_a.status

    # Verify New Method B
    method_b = @company.shipping_options.find_by(name: "New Method B")
    assert_not_nil method_b
    assert_equal 5, method_b.delivery_time
    assert_equal 8.99, method_b.starting_rate
    assert_equal [ "CA" ], method_b.countries
    assert_equal "active", method_b.status
  end

  test "should return failure when some rows succeed and some fail (all-or-nothing)" do
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,5,9.99,5.00
      Express Shipping,INVALID,NY,0,5,9.99,5.00
      Express Shipping,US,TX,0,10,12.99,8.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]
    assert_equal 0, result[:imported_count]
    assert result[:row_errors].present?
    assert_equal 1, result[:row_errors].count
    assert_includes result[:message], "Import failed"
    assert_includes result[:message], "No records were imported"
  end

  test "should sort CSV rows by shipping method, country, region, and min_range_lbs" do
    # CSV with deliberately unsorted rows
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,NY,5,10,14.99,10.00
      Express Shipping,US,CA,10,25,24.99,15.00
      Express Shipping,US,CA,0,5,9.99,5.00
      Express Shipping,US,NY,0,5,12.99,8.00
      Express Shipping,US,CA,5,10,14.99,10.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success], "Import should succeed with sorted data"
    assert_equal 5, result[:imported_count]

    # Verify CA rates are imported correctly (sorted)
    ca_rates = @shipping_option.rates.where(country: "US", region: "CA").order(:min_range_lbs)
    assert_equal 3, ca_rates.count
    assert_equal 0, ca_rates[0].min_range_lbs
    assert_equal 5, ca_rates[1].min_range_lbs
    assert_equal 10, ca_rates[2].min_range_lbs

    # Verify NY rates are imported correctly (sorted)
    ny_rates = @shipping_option.rates.where(country: "US", region: "NY").order(:min_range_lbs)
    assert_equal 2, ny_rates.count
    assert_equal 0, ny_rates[0].min_range_lbs
    assert_equal 5, ny_rates[1].min_range_lbs
  end

  test "should update existing shipping option with new countries from CSV" do
    # Ensure shipping option exists with US only
    existing_option = @company.shipping_options.find_by(name: "Express Shipping")
    existing_option.update!(countries: [ "US" ])

    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,CA,,0,10,15.99,10.00
      Express Shipping,MX,,0,8,18.99,12.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 2, result[:imported_count]

    # Verify shipping option now has all countries
    existing_option.reload
    assert_equal %w[CA MX US], existing_option.countries.sort
  end

  # === Upsert / Replace behavior tests ===

  test "should replace existing rates for the same shipping option, country, and region" do
    # Create existing rates for Express Shipping, US, CA
    @shipping_option.rates.create!(
      country: "US", region: "CA", min_range_lbs: 0, max_range_lbs: 5, flat_rate: 10.00, min_charge: 5.00
    )
    @shipping_option.rates.create!(
      country: "US", region: "CA", min_range_lbs: 5, max_range_lbs: 10, flat_rate: 15.00, min_charge: 8.00
    )

    assert_equal 2, @shipping_option.rates.where(country: "US", region: "CA").count

    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,10,12.99,6.00
      Express Shipping,US,CA,10,20,18.99,10.00
      Express Shipping,US,CA,20,50,25.99,15.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 3, result[:imported_count]
    assert_equal 2, result[:replaced_count]

    # Old rates should be gone, new rates should be present
    rates = @shipping_option.rates.where(country: "US", region: "CA").order(:min_range_lbs)
    assert_equal 3, rates.count
    assert_equal 12.99, rates.first.flat_rate
    assert_equal 18.99, rates.second.flat_rate
    assert_equal 25.99, rates.third.flat_rate
  end

  test "should not affect rates for locations not in the CSV" do
    # Create rates for two locations
    @shipping_option.rates.create!(
      country: "US", region: "CA", min_range_lbs: 0, max_range_lbs: 10, flat_rate: 10.00, min_charge: 5.00
    )
    @shipping_option.rates.create!(
      country: "US", region: "NY", min_range_lbs: 0, max_range_lbs: 10, flat_rate: 12.00, min_charge: 6.00
    )

    # Only import for CA — NY should remain untouched
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,5,9.99,5.00
      Express Shipping,US,CA,5,15,14.99,8.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 2, result[:imported_count]
    assert_equal 1, result[:replaced_count]

    # CA rates were replaced
    ca_rates = @shipping_option.rates.where(country: "US", region: "CA").order(:min_range_lbs)
    assert_equal 2, ca_rates.count
    assert_equal 9.99, ca_rates.first.flat_rate

    # NY rate is untouched
    ny_rates = @shipping_option.rates.where(country: "US", region: "NY")
    assert_equal 1, ny_rates.count
    assert_equal 12.00, ny_rates.first.flat_rate
  end

  test "should rollback replaced rates when validation fails" do
    # Create existing rate
    @shipping_option.rates.create!(
      country: "US", region: "TX", min_range_lbs: 0, max_range_lbs: 10, flat_rate: 10.00, min_charge: 5.00
    )

    # Import with an invalid row — everything should rollback
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,TX,0,5,9.99,5.00
      Express Shipping,INVALID,TX,0,5,9.99,5.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert_not result[:success]

    # Original rate should still exist (rollback)
    tx_rates = @shipping_option.rates.where(country: "US", region: "TX")
    assert_equal 1, tx_rates.count
    assert_equal 10.00, tx_rates.first.flat_rate
  end

  test "should handle mix of new locations and replacement locations" do
    # Create existing rate for US/CA
    @shipping_option.rates.create!(
      country: "US", region: "CA", min_range_lbs: 0, max_range_lbs: 10, flat_rate: 10.00, min_charge: 5.00
    )

    # Import replaces US/CA and adds new US/FL
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,15,12.99,6.00
      Express Shipping,US,FL,0,10,8.99,4.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 2, result[:imported_count]
    assert_equal 1, result[:replaced_count]

    # CA was replaced
    ca_rates = @shipping_option.rates.where(country: "US", region: "CA")
    assert_equal 1, ca_rates.count
    assert_equal 12.99, ca_rates.first.flat_rate

    # FL was created
    fl_rates = @shipping_option.rates.where(country: "US", region: "FL")
    assert_equal 1, fl_rates.count
    assert_equal 8.99, fl_rates.first.flat_rate
  end

  test "should treat country-level rates (nil region) separately from regional rates" do
    # Create country-level rate (no region)
    @shipping_option.rates.create!(
      country: "US", region: nil, min_range_lbs: 0, max_range_lbs: 10, flat_rate: 5.00, min_charge: 2.00
    )
    # Create regional rate
    @shipping_option.rates.create!(
      country: "US", region: "CA", min_range_lbs: 0, max_range_lbs: 10, flat_rate: 10.00, min_charge: 5.00
    )

    # Only import country-level — regional should be untouched
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,,0,20,7.99,3.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_equal 1, result[:imported_count]
    assert_equal 1, result[:replaced_count]

    # Country-level rate was replaced
    country_rates = @shipping_option.rates.where(country: "US", region: nil)
    assert_equal 1, country_rates.count
    assert_equal 7.99, country_rates.first.flat_rate

    # Regional rate untouched
    ca_rates = @shipping_option.rates.where(country: "US", region: "CA")
    assert_equal 1, ca_rates.count
    assert_equal 10.00, ca_rates.first.flat_rate
  end

  test "should not affect rates belonging to a different company" do
    other_company = companies(:globex)
    other_option = other_company.shipping_options.create!(
      name: "Express Shipping",
      delivery_time: 5,
      starting_rate: 5.0,
      countries: [ "US" ],
      status: "active"
    )
    other_rate = other_option.rates.create!(
      country: "US", region: "CA", min_range_lbs: 0, max_range_lbs: 10,
      flat_rate: 99.99, min_charge: 50.00
    )

    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,10,12.99,6.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]

    # Other company's rate must be untouched
    assert_equal 99.99, other_rate.reload.flat_rate
  end

  test "should replace existing rates when applying auto-corrections" do
    @shipping_option.rates.create!(
      country: "US", region: "CA", min_range_lbs: 0, max_range_lbs: 10, flat_rate: 10.00, min_charge: 5.00
    )

    # CSV with an oversized weight value that is auto-correctable
    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,99999,12.99,6.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    # First call without corrections — should report auto-correctable errors
    result = service.call
    assert_not result[:success]
    assert result[:row_errors].any? { |e| e[:auto_correctable] }

    # Re-read and call with corrections applied
    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call(apply_corrections: true)

    assert result[:success]
    assert_equal 1, result[:imported_count]
    assert_equal 1, result[:replaced_count]

    # Original rate should be replaced, corrected max_range should be 9999.9999
    ca_rates = @shipping_option.rates.where(country: "US", region: "CA")
    assert_equal 1, ca_rates.count
    assert_equal 12.99, ca_rates.first.flat_rate
    assert_equal BigDecimal("9999.9999"), ca_rates.first.max_range_lbs
  end

  test "success message includes replaced count when rates were replaced" do
    @shipping_option.rates.create!(
      country: "US", region: "CA", min_range_lbs: 0, max_range_lbs: 10, flat_rate: 10.00, min_charge: 5.00
    )

    csv_content = <<~CSV
      shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
      Express Shipping,US,CA,0,10,12.99,6.00
    CSV

    file = create_csv_file(csv_content)
    service = RateCsvImportService.new(company: @company, file: file)

    result = service.call

    assert result[:success]
    assert_includes result[:message], "1 existing rate(s) replaced"
  end

  test "should handle CSV files with UTF-8 BOM" do
    bom = "\xEF\xBB\xBF"
    csv_content = "#{bom}shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge\n" \
                  "Express Shipping,US,CA,0,5,9.99,5.00\n"

    file = Tempfile.new([ "test_bom", ".csv" ])
    file.binmode
    file.write(csv_content)
    file.rewind
    uploaded = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "bom_test.csv")

    service = RateCsvImportService.new(company: @company, file: uploaded)
    result = service.call

    assert result[:success], "Expected success but got: #{result[:message]} #{result[:errors]}"
    assert_equal 1, result[:imported_count]
  end

private

  def create_csv_file(content)
    file = Tempfile.new([ "test", ".csv" ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "test.csv")
  end
end
