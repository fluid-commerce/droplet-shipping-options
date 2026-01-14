class Company < ApplicationRecord
  has_many :events, dependent: :destroy
  has_one :integration_setting, dependent: :destroy
  has_many :shipping_options, dependent: :destroy
  has_many :rates, through: :shipping_options

  validates :fluid_shop, :authentication_token, :name, :fluid_company_id, :company_droplet_uuid, presence: true
  validates :authentication_token, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :installed, -> { where(uninstalled_at: nil) }
  scope :uninstalled, -> { where.not(uninstalled_at: nil) }

  after_initialize :set_defaults, if: :new_record?

  # Check if the company's droplet installation is currently active and installed
  def installed?
    uninstalled_at.nil? && active?
  end

  # Check if the company's droplet has been uninstalled
  def uninstalled?
    uninstalled_at.present?
  end

private

  def set_defaults
    self.installed_callback_ids ||= []
    self.previous_dris ||= []
  end
end
