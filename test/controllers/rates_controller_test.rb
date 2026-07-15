require "test_helper"

class RatesControllerTest < ActionDispatch::IntegrationTest
  fixtures :companies

  test "gets index with dri parameter" do
    get rate_tables_url, params: { dri: "test-dri" }
    assert_response :success
  end

  test "gets new with dri parameter" do
    get new_rate_table_url, params: { dri: "test-dri" }
    # Puede ser success o redirect, pero no debe ser 400 Bad Request
    assert_not_equal 400, response.status
  end

  test "gets create with dri parameter" do
    post rate_tables_url, params: { dri: "test-dri", rate: { country: "" } }
    # Puede ser success o redirect, pero no debe ser 400 Bad Request
    assert_not_equal 400, response.status
  end

  test "gets edit with dri parameter" do
    get edit_rate_table_url(id: 1), params: { dri: "test-dri" }
    # Puede ser success o redirect, pero no debe ser 400 Bad Request
    assert_not_equal 400, response.status
  end

  test "gets update with dri parameter" do
    patch rate_table_url(id: 1), params: { dri: "test-dri" }
    # Puede ser success o redirect, pero no debe ser 400 Bad Request
    assert_not_equal 400, response.status
  end

  test "gets destroy with dri parameter" do
    delete rate_table_url(id: 1), params: { dri: "test-dri" }
    # Puede ser success o redirect, pero no debe ser 400 Bad Request
    assert_not_equal 400, response.status
  end

  test "process_import successfully imports a CSV with non-UTF-8 bytes (Sentry DROPLET-SHIPPING-OPTIONS-1)" do
    # Reproduces the Sentry crash scenario: a CSV exported from Excel/another tool can
    # contain Windows-1252/raw binary bytes (e.g. a lone 0xC2) that are not valid UTF-8.
    #
    # `String#force_encoding("UTF-8")` only relabels the bytes as UTF-8 without converting
    # them, so the string stays invalid UTF-8 all the way through import. That silently
    # sends the row through `CSV.parse`, which raises `CSV::InvalidEncodingError` when it
    # hits the bad byte, and `RateCsvImportService#read_csv_file` rescues that as a plain
    # "Unable to read CSV file" failure (HTTP 422) instead of importing the row.
    #
    # `String#encode("UTF-8", "binary", invalid: :replace, undef: :replace)` actually
    # transcodes the bytes, replacing the undecodable one with the Unicode replacement
    # character, so the row is genuinely valid UTF-8 and the import succeeds.
    csv_bytes = (+"shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge\n" \
                  "Expr\xC2ess Shipping,US,CA,0,5,9.99,5.00\n").force_encoding(Encoding::ASCII_8BIT)

    file = Tempfile.new([ "test_non_utf8", ".csv" ])
    file.binmode
    file.write(csv_bytes)
    file.rewind
    uploaded = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "non_utf8.csv")

    assert_difference -> { Rate.count }, 1 do
      post process_import_rate_tables_url, params: { dri: "test-dri", csv_file: uploaded }
    end

    assert_response :redirect
    assert_match(/Successfully imported/, flash[:notice])

    imported_method = Rate.joins(:shipping_option).order(created_at: :desc).first.shipping_option.name
    assert imported_method.valid_encoding?
    assert imported_method.start_with?("Expr")
  end
end
