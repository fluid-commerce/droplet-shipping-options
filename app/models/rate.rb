class Rate < ApplicationRecord
  belongs_to :shipping_option

  validates :country, presence: true
  validates :min_range_lbs, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_range_lbs, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :flat_rate, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :min_charge, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :for_country, ->(country_code) { where(country: country_code) }
  scope :for_region, ->(region_code) { where(region: region_code) }
  scope :general_country_rates, -> { where(region: [ nil, "" ]) }

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
end
