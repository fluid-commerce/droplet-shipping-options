require "test_helper"

class RatesControllerTest < ActionDispatch::IntegrationTest
  fixtures :companies

  CSV_IMPORT_HEADER = "shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge\n".freeze

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
    # Transcoding the bytes from Windows-1252 makes the string genuinely valid UTF-8,
    # so the row survives CSV parsing and the import succeeds.
    csv_bytes = CSV_IMPORT_HEADER.b + "Expr\xC2ess Shipping,US,CA,0,5,9.99,5.00\n".b
    uploaded = uploaded_csv(csv_bytes, "non_utf8.csv")

    assert_difference -> { Rate.count }, 1 do
      post process_import_rate_tables_url, params: { dri: "test-dri", csv_file: uploaded }
    end

    assert_response :redirect
    assert_match(/Successfully imported/, flash[:notice])

    imported_method = Rate.joins(:shipping_option).order(created_at: :desc).first.shipping_option.name
    assert imported_method.valid_encoding?
    assert imported_method.start_with?("Expr")
  end

  test "process_import preserves valid UTF-8 multi-byte characters" do
    # Guards against transcoding the upload as if every byte stood alone: a file that is
    # already valid UTF-8 must pass through byte for byte, instead of having each byte of
    # a multi-byte character turned into a replacement character.
    csv_bytes = CSV_IMPORT_HEADER.b + "Caf\xC3\xA9 Express,US,CA,0,5,9.99,5.00\n".b
    uploaded = uploaded_csv(csv_bytes, "utf8.csv")

    assert_difference -> { Rate.count }, 1 do
      post process_import_rate_tables_url, params: { dri: "test-dri", csv_file: uploaded }
    end

    assert_response :redirect
    assert ShippingOption.exists?(name: "Café Express"), "expected the UTF-8 name to survive unchanged"
  end

  test "process_import transcodes Windows-1252 content carrying a UTF-8 BOM" do
    # Excel exports frequently carry a UTF-8 BOM and Windows-1252 high bytes. The BOM must
    # be stripped at the byte level, before anything relabels it, and the 0xF1 byte must
    # become "ñ" rather than a replacement character.
    csv_bytes = "\xEF\xBB\xBF".b + CSV_IMPORT_HEADER.b + "Se\xF1or Freight,US,NY,0,5,9.99,5.00\n".b
    uploaded = uploaded_csv(csv_bytes, "cp1252_bom.csv")

    assert_difference -> { Rate.count }, 1 do
      post process_import_rate_tables_url, params: { dri: "test-dri", csv_file: uploaded }
    end

    assert_response :redirect
    assert ShippingOption.exists?(name: "Señor Freight"), "expected Windows-1252 bytes to be transcoded"
  end

private

  def uploaded_csv(bytes, filename)
    file = Tempfile.new([ "test_csv_import", ".csv" ])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: filename)
  end
end
