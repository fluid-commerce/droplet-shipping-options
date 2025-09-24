require "test_helper"

class RateTest < ActiveSupport::TestCase
  def setup
    @rate = rates(:one)
  end

  test "should be valid" do
    assert @rate.valid?
  end

  describe "validations" do
    test "country should be present" do
      @rate.country = nil
      assert_not @rate.valid?
      assert_includes @rate.errors[:country], "can't be blank"
    end

    test "country should be 2 characters long" do
      @rate.country = "USA"
      assert_not @rate.valid?
      assert_includes @rate.errors[:country], "is the wrong length (should be 2 characters)"
    end


    test "region should be present" do
      @rate.region = nil
      assert_not @rate.valid?
      assert_includes @rate.errors[:region], "can't be blank"
    end

    test "min_range_lbs should be present" do
      @rate.min_range_lbs = nil
      assert_not @rate.valid?
      assert_includes @rate.errors[:min_range_lbs], "can't be blank"
    end

    test "min_range_lbs should be greater than or equal to 0" do
      @rate.min_range_lbs = -1
      assert_not @rate.valid?
      assert_includes @rate.errors[:min_range_lbs], "must be greater than or equal to 0"
    end

    test "max_range_lbs should be present" do
      @rate.max_range_lbs = nil
      assert_not @rate.valid?
      assert_includes @rate.errors[:max_range_lbs], "can't be blank"
    end

    test "max_range_lbs should be greater than 0" do
      @rate.max_range_lbs = 0
      assert_not @rate.valid?
      assert_includes @rate.errors[:max_range_lbs], "must be greater than 0"
    end

    test "flat_rate should be present" do
      @rate.flat_rate = nil
      assert_not @rate.valid?
      assert_includes @rate.errors[:flat_rate], "can't be blank"
    end

    test "flat_rate should be greater than or equal to 0" do
      @rate.flat_rate = -1
      assert_not @rate.valid?
      assert_includes @rate.errors[:flat_rate], "must be greater than or equal to 0"
    end

    test "min_charge should be present" do
      @rate.min_charge = nil
      assert_not @rate.valid?
      assert_includes @rate.errors[:min_charge], "can't be blank"
    end

    test "min_charge should be greater than or equal to 0" do
      @rate.min_charge = -1
      assert_not @rate.valid?
      assert_includes @rate.errors[:min_charge], "must be greater than or equal to 0"
    end

    test "max_range_lbs should be greater than min_range_lbs" do
      @rate.min_range_lbs = 5.0
      @rate.max_range_lbs = 3.0
      assert_not @rate.valid?
      assert_includes @rate.errors[:max_range_lbs], "must be greater than min_range_lbs"
    end
  end

  describe "associations" do
    test "should belong to shipping_option" do
      assert_respond_to @rate, :shipping_option
      assert_equal shipping_options(:standard_shipping), @rate.shipping_option
    end
  end


  describe "instance methods" do
    test "weight_range should return formatted weight range" do
      assert_equal "0.0 - 5.0 lbs", @rate.weight_range
    end
  end

  describe "uniqueness validation" do
    test "should not allow overlapping weight ranges for same shipping option and location" do
      duplicate_rate = Rate.new(
        shipping_option: @rate.shipping_option,
        country: @rate.country,
        region: @rate.region,
        min_range_lbs: 1.0,
        max_range_lbs: 2.0,
        flat_rate: 15.00,
        min_charge: 5.00
      )

      assert_not duplicate_rate.valid?
      assert duplicate_rate.errors[:base].any? { |error| error.include?("Weight range overlaps with existing rate") }
    end

    test "should allow same shipping option for different locations" do
      different_location_rate = Rate.new(
        shipping_option: @rate.shipping_option,
        country: "CA",
        region: "ON",
        min_range_lbs: 0, # First rate must start at 0
        max_range_lbs: 5.0,
        flat_rate: 20.00,
        min_charge: 10.00
      )

      assert different_location_rate.valid?
    end
  end
end
