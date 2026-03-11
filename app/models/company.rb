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

  store_accessor :settings, :exigo_db_server, :exigo_db_name, :exigo_db_user, :exigo_db_password,
                 :exigo_subscription_id, :free_shipping_for_subscribers

  def exigo_db_password=(value)
    super(value.present? ? self.class.password_encryptor.encrypt_and_sign(value) : value)
  end

  def exigo_db_password
    raw = super
    return raw if raw.blank?
    self.class.password_encryptor.decrypt_and_verify(raw)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    raw
  end

  def self.password_encryptor
    @password_encryptor ||= begin
      key = ActiveSupport::KeyGenerator.new(
        Rails.application.secret_key_base,
        iterations: 1000
      ).generate_key("exigo_db_password_encryption", 32)
      ActiveSupport::MessageEncryptor.new(key)
    end
  end

  # Check if the company's droplet installation is currently active and installed
  def installed?
    uninstalled_at.nil? && active?
  end

  # Check if the company's droplet has been uninstalled
  def uninstalled?
    uninstalled_at.present?
  end

  def free_shipping_enabled?
    free_shipping_for_subscribers == "true" || free_shipping_for_subscribers == true
  end

private

  def set_defaults
    self.installed_callback_ids ||= []
    self.previous_dris ||= []
  end
end
