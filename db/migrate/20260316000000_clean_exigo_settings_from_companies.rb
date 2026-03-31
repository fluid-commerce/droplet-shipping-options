# frozen_string_literal: true

class CleanExigoSettingsFromCompanies < ActiveRecord::Migration[8.0]
  def up
    Company.find_each do |company|
      next if company.settings.blank?

      %w[
        exigo_db_server exigo_db_name exigo_db_user
        exigo_db_password exigo_subscription_id
        fluid_subscription_product_id
      ].each { |key| company.settings.delete(key) }

      company.save!(validate: false)
    end
  end

  def down
    # No-op: cannot restore deleted settings
  end
end
