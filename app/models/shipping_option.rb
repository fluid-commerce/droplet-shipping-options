class ShippingOption < ApplicationRecord
  belongs_to :company
  has_many :rates, dependent: :destroy

  validates :name, presence: true
  validates :delivery_time, presence: true, numericality: { greater_than: 0 }
  validates :starting_rate, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :countries, presence: true
  validates :status, presence: true, inclusion: { in: %w[active inactive draft] }

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
end
