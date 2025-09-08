class Rate < ApplicationRecord
  belongs_to :shipping_option

  validates :ship_method_id, presence: true, numericality: { greater_than: 0 }
  validates :country, presence: true, length: { is: 2 }
  validates :region, length: { maximum: 10 }
  validates :min_range_lbs, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_range_lbs, presence: true, numericality: { greater_than: 0 }
  validates :flat_rate, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :min_charge, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :max_range_greater_than_min_range
  validate :unique_rate_per_method_and_location

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

  def unique_rate_per_method_and_location
    return unless shipping_option_id.present? && ship_method_id.present? && country.present?

    existing_rate = Rate.where(
      shipping_option_id: shipping_option_id,
      ship_method_id: ship_method_id,
      country: country,
      region: region
    ).where.not(id: id)

    if existing_rate.exists?
      errors.add(:base, "Rate already exists for this method and location")
    end
  end
end
