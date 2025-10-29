class ShippingOption < ApplicationRecord
  belongs_to :company
  has_many :rates, dependent: :destroy

  validates :name, presence: true
  validates :delivery_time, presence: true, numericality: { greater_than: 0 }
  validates :starting_rate, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :countries, presence: true
  validates :status, presence: true, inclusion: { in: %w[active inactive draft] }

  validate :unique_name_per_company_and_countries

  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where(status: "inactive") }
  scope :for_country, ->(country_code) { where("countries @> ?", [ country_code ].to_json) }

  def active?
    status == "active"
  end

  def inactive?
    status == "inactive"
  end

  def disable!
    update!(status: "inactive")
  end

  def enable!
    update!(status: "active")
  end

  def toggle_status!
    active? ? disable! : enable!
  end

  def countries=(value)
    if value.is_a?(String)
      super(value.split(",").map(&:strip).reject(&:blank?))
    else
      super(value)
    end
  end

private

  def unique_name_per_company_and_countries
    return unless name.present? && company.present? && countries.present?

    # Find shipping options with the same name for this company
    existing_options = ShippingOption.where(company: company, name: name)
                                     .where.not(id: id)

    # Check if any of the existing options have overlapping countries
    existing_options.each do |option|
      overlapping_countries = (countries & option.countries)
      if overlapping_countries.any?
        errors.add(:name, "already exists for #{overlapping_countries.join(', ')}")
        break
      end
    end
  end
end
