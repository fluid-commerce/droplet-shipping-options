class ShippingOption < ApplicationRecord
  belongs_to :company
  has_many :rates, dependent: :destroy

  validates :name, presence: true
  validates :delivery_time, presence: true, numericality: { greater_than: 0 }
  validates :starting_rate, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :countries, presence: true
  validates :status, presence: true, inclusion: { in: %w[active inactive draft] }

  scope :active, -> { where(status: 'active') }

  def active?
    status == 'active'
  end


  def countries=(value)
    if value.is_a?(String)
      super(value.split(',').map(&:strip).reject(&:blank?))
    else
      super(value)
    end
  end
end
