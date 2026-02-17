require "test_helper"

class Api::GeographyControllerTest < ActionDispatch::IntegrationTest
  fixtures :companies

  setup do
    @company = companies(:acme)
    @dri = @company.droplet_installation_uuid

    @mock_countries = [
      { "id" => 1, "name" => "United States", "iso" => "US" },
      { "id" => 2, "name" => "Canada", "iso" => "CA" },
      { "id" => 3, "name" => "Philippines", "iso" => "PH" },
    ]

    @mock_states = [
      { "id" => 10, "name" => "California", "country_id" => 1 },
      { "id" => 11, "name" => "Texas", "country_id" => 1 },
    ]

    Rails.cache.clear
  end

  # ============================================
  # GET /api/geography/countries
  # ============================================

  test "countries returns expected format" do
    stub_fluid_client(countries: @mock_countries) do
      get api_geography_countries_url, params: { dri: @dri }
    end

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 3, json.length
    first = json.first
    assert first.key?("value")
    assert first.key?("label")
    assert_not first.key?("id")
  end

  test "countries are sorted by label" do
    stub_fluid_client(countries: @mock_countries) do
      get api_geography_countries_url, params: { dri: @dri }
    end

    assert_response :success
    json = JSON.parse(response.body)
    labels = json.map { |c| c["label"] }

    assert_equal labels.sort, labels
  end

  test "countries returns label with ISO code in parens" do
    stub_fluid_client(countries: @mock_countries) do
      get api_geography_countries_url, params: { dri: @dri }
    end

    assert_response :success
    json = JSON.parse(response.body)

    us = json.find { |c| c["value"] == "US" }
    assert_equal "United States (US)", us["label"]
  end

  test "countries without DRI returns error" do
    get api_geography_countries_url

    assert_response :not_found
  end

  test "countries returns empty array on FluidClient error" do
    client = stub_client_that_raises(FluidClient::APIError.new("Server error"))

    FluidClient.stub(:new, client) do
      get api_geography_countries_url, params: { dri: @dri }
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [], json
  end

  test "countries caches FluidClient response" do
    call_count = 0
    fake_client = lambda_client do |path, _opts|
      if path == "/api/countries"
        call_count += 1
        @mock_countries
      end
    end

    # Test env uses :null_store, swap in memory store to verify caching
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    FluidClient.stub(:new, fake_client) do
      get api_geography_countries_url, params: { dri: @dri }
      assert_response :success

      get api_geography_countries_url, params: { dri: @dri }
      assert_response :success
    end

    assert_equal 1, call_count, "FluidClient should only be called once due to caching"
  ensure
    Rails.cache = original_cache
  end

  # ============================================
  # GET /api/geography/states
  # ============================================

  test "states returns full state names" do
    stub_fluid_client(countries: @mock_countries, states: { 1 => @mock_states }) do
      get api_geography_states_url, params: { dri: @dri, country_code: "US" }
    end

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 2, json.length
    assert_equal "California", json.first["value"]
    assert_equal "California", json.first["label"]
  end

  test "states with missing country_code returns empty array" do
    get api_geography_states_url, params: { dri: @dri }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [], json
  end

  test "states with unknown country_code returns empty array" do
    stub_fluid_client(countries: @mock_countries) do
      get api_geography_states_url, params: { dri: @dri, country_code: "ZZ" }
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [], json
  end

  test "states without DRI returns error" do
    get api_geography_states_url, params: { country_code: "US" }

    assert_response :not_found
  end

  test "states returns empty array on FluidClient error" do
    call_count = 0
    fake_client = lambda_client do |path, opts|
      call_count += 1
      if path == "/api/countries"
        @mock_countries
      else
        raise FluidClient::APIError, "Server error"
      end
    end

    FluidClient.stub(:new, fake_client) do
      get api_geography_states_url, params: { dri: @dri, country_code: "US" }
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [], json
  end

  test "states normalizes country_code to uppercase" do
    stub_fluid_client(countries: @mock_countries, states: { 1 => @mock_states }) do
      get api_geography_states_url, params: { dri: @dri, country_code: "us" }
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 2, json.length
  end

private

  # Creates a fake client object that delegates get() to a block
  def lambda_client(&block)
    client = Object.new
    client.define_singleton_method(:get) do |path, opts = {}|
      block.call(path, opts)
    end
    client
  end

  # Raises on any get() call
  def stub_client_that_raises(error)
    lambda_client { |_path, _opts| raise error }
  end

  # Stubs FluidClient with preconfigured responses for countries and states
  # states should be a hash of { country_id => states_array }
  def stub_fluid_client(countries: [], states: {}, &block)
    fake = lambda_client do |path, opts|
      case path
      when "/api/countries"
        countries
      when "/api/states"
        country_id = opts.dig(:query, :country_id)
        states[country_id] || []
      end
    end

    FluidClient.stub(:new, fake, &block)
  end
end
