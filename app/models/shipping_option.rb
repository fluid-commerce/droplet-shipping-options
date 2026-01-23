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
  scope :ordered_for_country, ->(country_code) {
    order(
      Arel.sql(
        "COALESCE((country_sort_positions->>#{connection.quote(country_code)})::integer, 2147483647) ASC, id ASC"
      )
    )
  }

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

  # Get position for a specific country (fallback to nil if not set)
  def position_for_country(country_code)
    country_sort_positions&.dig(country_code)
  end

  # Set position for a specific country
  def set_position_for_country(country_code, position)
    self.country_sort_positions ||= {}
    self.country_sort_positions[country_code] = position
  end

  after_create :assign_default_sort_positions
  after_commit :invalidate_cache!

  # Invalidates the shipping options cache for all countries this option serves.
  # Also invalidates cache for any countries that were removed during an update.
  def invalidate_cache!
    countries_to_invalidate = Array(countries)

    # Also invalidate removed countries on update
    if previous_changes["countries"].present?
      old_countries = previous_changes["countries"].first || []
      countries_to_invalidate = (countries_to_invalidate + Array(old_countries)).uniq
    end

    countries_to_invalidate.each do |country|
      Rails.cache.delete("shipping_opts:#{company_id}:#{country}")
    end
  end

private


  def assign_default_sort_positions
    return if countries.blank?

    countries.each do |country_code|
      # Find the max position for this country across company's shipping options
      quoted_country = self.class.connection.quote(country_code)
      max_position = company.shipping_options
                            .where.not(id: id)
                            .where("country_sort_positions ? :country", country: country_code)
                            .maximum(Arel.sql("(country_sort_positions->>#{quoted_country})::integer"))

      next_position = (max_position || 0) + 1
      set_position_for_country(country_code, next_position)
    end

    save! if country_sort_positions_changed?
  end


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
