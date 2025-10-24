class DropletInstallationService
  def initialize(payload)
    @payload = payload
  end

  def call
    validate_payload
    company = find_or_create_company
    register_shipping_callback(company)
    { success: true, company: company }
  rescue => e
    Rails.logger.error("[DropletInstallationService] Error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    { success: false, error: e.message }
  end

private

  def validate_payload
    unless @payload["company"].present?
      raise ArgumentError, "Missing required payload key: company"
    end
  end

  def find_or_create_company
    company_attributes = @payload.fetch("company", {})
    company = Company.find_by(fluid_shop: company_attributes["fluid_shop"]) || Company.new

    # Log if this is a reinstallation
    if company.persisted? && company.droplet_installation_uuid != company_attributes["droplet_installation_uuid"]
      Rails.logger.info(
        "[DropletInstallationService] Reinstallation detected for #{company.fluid_shop}. " \
        "Old DRI: #{company.droplet_installation_uuid}, New DRI: #{company_attributes['droplet_installation_uuid']}"
      )
    end

    company.assign_attributes(company_attributes.slice(
      "fluid_shop",
      "name",
      "fluid_company_id",
      "authentication_token",
      "webhook_verification_token",
      "droplet_installation_uuid",
    ))
    company.company_droplet_uuid = company_attributes.fetch("droplet_uuid")
    company.active = true
    company.uninstalled_at = nil  # Clear uninstallation timestamp

    unless company.save
      raise "Failed to save company: #{company.errors.full_messages.join(', ')}"
    end

    company
  end

  def register_shipping_callback(company)
    client = FluidClient.new

    # Always register the shipping options callback - required for droplet functionality
    base_url = ENV.fetch("DROPLET_URL", "https://fluid-droplet-shipping-options-106074092699.europe-west1.run.app")
    callback = {
      definition_name: "shipping_options",
      url: "#{base_url}/callbacks/shipping_options",
      timeout_in_seconds: 10,
      active: true,
    }

    Rails.logger.info(
      "[DropletInstallationService] Registering required callback: " \
      "#{callback[:definition_name]} at #{callback[:url]}"
    )

    response = client.callback_registrations.create(callback)
    if response && response["callback_registration"]["uuid"]
      callback_uuid = response["callback_registration"]["uuid"]
      company.update(installed_callback_ids: [ callback_uuid ])
      Rails.logger.info(
        "[DropletInstallationService] Successfully registered callback with UUID: #{callback_uuid}"
      )
    else
      Rails.logger.warn(
        "[DropletInstallationService] Callback registered but no UUID returned"
      )
    end
  rescue => e
    # Log error but don't fail the installation
    Rails.logger.error(
      "[DropletInstallationService] Failed to register callback: #{e.message}"
    )
    Rails.logger.error(e.backtrace.join("\n"))
    raise e  # Re-raise so installation fails if callback fails
  end
end
