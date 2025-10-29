require "test_helper"

class ShippingOptionTest < ActiveSupport::TestCase
  def setup
    @company = companies(:acme)
    @shipping_option = ShippingOption.new(
      name: "Test Shipping Method",
      delivery_time: 2,
      starting_rate: 15.99,
      countries: %w[GB DE],
      status: "active",
      company: @company
    )
  end

  test "should be valid with valid attributes" do
    assert @shipping_option.valid?
  end

  test "should require name" do
    @shipping_option.name = nil
    assert_not @shipping_option.valid?
    assert_includes @shipping_option.errors[:name], "can't be blank"
  end

  test "should require delivery_time" do
    @shipping_option.delivery_time = nil
    assert_not @shipping_option.valid?
    assert_includes @shipping_option.errors[:delivery_time], "can't be blank"
  end

  test "should require delivery_time to be greater than 0" do
    @shipping_option.delivery_time = 0
    assert_not @shipping_option.valid?
    assert_includes @shipping_option.errors[:delivery_time], "must be greater than 0"
  end

  test "should require delivery_time to be positive" do
    @shipping_option.delivery_time = -1
    assert_not @shipping_option.valid?
    assert_includes @shipping_option.errors[:delivery_time], "must be greater than 0"
  end

  test "should require starting_rate" do
    @shipping_option.starting_rate = nil
    assert_not @shipping_option.valid?
    assert_includes @shipping_option.errors[:starting_rate], "can't be blank"
  end

  test "should require starting_rate to be non-negative" do
    @shipping_option.starting_rate = -1
    assert_not @shipping_option.valid?
    assert_includes @shipping_option.errors[:starting_rate], "must be greater than or equal to 0"
  end

  test "should require countries" do
    @shipping_option.countries = nil
    assert_not @shipping_option.valid?
    assert_includes @shipping_option.errors[:countries], "can't be blank"
  end

  test "should require status" do
    @shipping_option.status = nil
    assert_not @shipping_option.valid?
    assert_includes @shipping_option.errors[:status], "can't be blank"
  end

  test "should require valid status" do
    @shipping_option.status = "invalid_status"
    assert_not @shipping_option.valid?
    assert_includes @shipping_option.errors[:status], "is not included in the list"
  end

  test "should accept valid statuses" do
    valid_statuses = %w[active inactive draft]
    valid_statuses.each do |status|
      @shipping_option.status = status
      assert @shipping_option.valid?, "#{status} should be valid"
    end
  end

  test "should belong to company" do
    @shipping_option.company = nil
    assert_not @shipping_option.valid?
    assert_includes @shipping_option.errors[:company], "must exist"
  end

  test "active scope should return active shipping options" do
    active_option = ShippingOption.create!(
      name: "Active Option",
      delivery_time: 1,
      starting_rate: 10.00,
      countries: %w[US],
      status: "active",
      company: @company
    )

    inactive_option = ShippingOption.create!(
      name: "Inactive Option",
      delivery_time: 1,
      starting_rate: 10.00,
      countries: %w[US],
      status: "inactive",
      company: @company
    )

    assert_includes ShippingOption.active, active_option
    assert_not_includes ShippingOption.active, inactive_option
  end

  test "active? method should return true for active status" do
    @shipping_option.status = "active"
    assert @shipping_option.active?
  end

  test "should allow duplicate names for different countries" do
    # Create first shipping option with GB and DE
    first_option = ShippingOption.create!(
      name: "International Express",
      delivery_time: 5,
      starting_rate: 9.99,
      countries: %w[GB DE],
      status: "active",
      company: @company
    )

    # Should be able to create another with same name but different countries
    second_option = ShippingOption.new(
      name: "International Express",
      delivery_time: 5,
      starting_rate: 9.99,
      countries: %w[FR ES],
      status: "active",
      company: @company
    )

    assert second_option.valid?
    assert second_option.save
  end

  test "should not allow duplicate names with same countries" do
    # Create first shipping option
    ShippingOption.create!(
      name: "Fast Delivery",
      delivery_time: 2,
      starting_rate: 19.99,
      countries: %w[JP KR],
      status: "active",
      company: @company
    )

    # Try to create another with same name and same countries
    duplicate_option = ShippingOption.new(
      name: "Fast Delivery",
      delivery_time: 3,
      starting_rate: 29.99,
      countries: %w[JP KR],
      status: "active",
      company: @company
    )

    assert_not duplicate_option.valid?
    assert_includes duplicate_option.errors[:name], "already exists for JP, KR"
  end

  test "should not allow duplicate names with overlapping countries" do
    # Create first shipping option with AU and NZ
    ShippingOption.create!(
      name: "Pacific Express",
      delivery_time: 3,
      starting_rate: 14.99,
      countries: %w[AU NZ],
      status: "active",
      company: @company
    )

    # Try to create another with same name and one overlapping country
    overlapping_option = ShippingOption.new(
      name: "Pacific Express",
      delivery_time: 4,
      starting_rate: 24.99,
      countries: %w[NZ FJ],
      status: "active",
      company: @company
    )

    assert_not overlapping_option.valid?
    assert_includes overlapping_option.errors[:name], "already exists for NZ"
  end

  test "should allow same name for different companies" do
    other_company = companies(:globex)

    # Create shipping option for first company
    ShippingOption.create!(
      name: "Global Standard",
      delivery_time: 7,
      starting_rate: 5.99,
      countries: %w[CN IN],
      status: "active",
      company: @company
    )

    # Should be able to create same name with same country for different company
    other_option = ShippingOption.new(
      name: "Global Standard",
      delivery_time: 7,
      starting_rate: 5.99,
      countries: %w[CN IN],
      status: "active",
      company: other_company
    )

    assert other_option.valid?
  end

  test "should allow updating shipping option without triggering validation error" do
    option = ShippingOption.create!(
      name: "Next Day Air",
      delivery_time: 1,
      starting_rate: 39.99,
      countries: %w[SG MY],
      status: "active",
      company: @company
    )

    # Should be able to update other fields
    option.delivery_time = 2
    assert option.valid?
    assert option.save
  end
end
