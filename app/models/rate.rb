class Rate < ApplicationRecord
  belongs_to :shipping_option

  validates :country, presence: true, length: { is: 2 }
  validates :region, presence: true
  validates :min_range_lbs, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_range_lbs, presence: true, numericality: { greater_than: 0 }
  validates :flat_rate, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :min_charge, presence: true, numericality: { greater_than_or_equal_to: 0 }

  validate :max_range_greater_than_min_range
  validate :unique_rate_per_shipping_option_and_location

  scope :for_country, ->(country_code) { where(country: country_code) }
  scope :for_region, ->(region_code) { where(region: region_code) }

  def country_code
    country
  end

  def state_code
    region
  end

  def amount
    flat_rate
  end

  def weight_range
    "#{min_range_lbs} - #{max_range_lbs} lbs"
  end

private

  def max_range_greater_than_min_range
    return unless min_range_lbs.present? && max_range_lbs.present?

    if max_range_lbs <= min_range_lbs
      errors.add(:max_range_lbs, "must be greater than min_range_lbs")
    end
  end

  def unique_rate_per_shipping_option_and_location
    return unless shipping_option.present? && country.present?

    existing_rates = Rate.where(
      shipping_option: shipping_option,
      country: country,
      region: region
    ).where.not(id: id)

    if existing_rates.empty? && min_range_lbs != 0
      errors.add(:min_range_lbs, "must be 0 for the first rate of this shipping option and location")
      return
    end

    existing_rates.each do |existing_rate|
      if ranges_overlap?(existing_rate)
        errors.add(:base, "Weight range overlaps with existing rate " \
                          "(#{existing_rate.min_range_lbs}-#{existing_rate.max_range_lbs} lbs)")
        break
      end
    end
  end

private

  def ranges_overlap?(other_rate)
    my_min = min_range_lbs || 0
    my_max = max_range_lbs || Float::INFINITY
    other_min = other_rate.min_range_lbs || 0
    other_max = other_rate.max_range_lbs || Float::INFINITY

    my_min < other_max && other_min < my_max
  end
end
