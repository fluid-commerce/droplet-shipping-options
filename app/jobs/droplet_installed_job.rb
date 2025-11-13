class DropletInstalledJob < WebhookEventJob
  # payload - Hash received from the webhook controller.
  # Expected structure (example):
  # {
  #   "company" => {
  #     "fluid_shop" => "example.myshopify.com",
  #     "name" => "Example Shop",
  #     "fluid_company_id" => 123,
  #     "company_droplet_uuid" => "uuid",
  #     "authentication_token" => "token",
  #     "webhook_verification_token" => "verify",
  #   }
  # }
  def process_webhook
    # Validate required keys in payload
    validate_payload_keys("company")
    company_attributes = get_payload.fetch("company", {})

    company = Company.find_by(fluid_shop: company_attributes["fluid_shop"]) || Company.new

    # Log if this is a reinstallation
    if company.persisted? && company.droplet_installation_uuid != company_attributes["droplet_installation_uuid"]
      Rails.logger.info(
        "[DropletInstalledJob] Reinstallation detected for #{company.fluid_shop}. " \
        "Old DRI: #{company.droplet_installation_uuid}, New DRI: #{company_attributes['droplet_installation_uuid']}"
      )
    end

    company.assign_attributes(company_attributes.slice(
      "fluid_shop",
      "name",
      "fluid_company_id",
      "authentication_token",
      "webhook_verification_token",
      "droplet_installation_uuid"
    ))
    company.company_droplet_uuid = company_attributes.fetch("droplet_uuid")
    company.active = true
    company.uninstalled_at = nil  # Clear uninstallation timestamp

    unless company.save
      Rails.logger.error(
        "[DropletInstalledJob] Failed to create company: #{company.errors.full_messages.join(', ')}"
      )
      return
    end

    register_active_callbacks(company)
  end

private

  def register_active_callbacks(company)
    installed_callback_ids = []

    # CRITICAL: Must use the installation token for callback operations
    installation_token = company.authentication_token
    unless installation_token
      Rails.logger.error(
        "[DropletInstalledJob] No installation token for #{company.fluid_shop}, " \
        "cannot register callbacks"
      )
      return
    end

    # Clean up any existing callbacks before registering new ones
    # This is a defensive measure: if the previous uninstall failed or wasn't triggered,
    # old callbacks would remain and cause duplicates on reinstall
    CallbackCleanupService.new(company).call

    # Always register the shipping options callback - required for droplet functionality
    droplet_url = ENV.fetch("DROPLET_URL", "https://fluid-droplet-shipping-options-106074092699.europe-west1.run.app")
    api_base_url = Setting.fluid_api.base_url
    required_callback = {
      definition_name: "update_cart_shipping",
      url: "#{droplet_url}/callbacks/shipping_options",
      timeout_in_seconds: 10,
      active: true,
    }

    begin
      Rails.logger.info(
        "[DropletInstalledJob] Registering required callback: " \
        "#{required_callback[:definition_name]} at #{required_callback[:url]}"
      )

      # Check if a callback with this definition already exists (should be prevented by cleanup, but extra safety)
      check_response = HTTParty.get(
        "#{api_base_url}/api/callback/registrations?definition_name=#{required_callback[:definition_name]}",
        headers: {
          "Authorization" => "Bearer #{installation_token}",
          "Content-Type" => "application/json",
        }
      )
      if check_response.code == 200 && check_response["callback_registrations"]&.any?
        Rails.logger.warn(
          "[DropletInstalledJob] Found #{check_response['callback_registrations'].length} " \
          "existing callback(s) for #{required_callback[:definition_name]} after cleanup. " \
          "This should not happen - possible race condition or cleanup failure."
        )
      end

      response = HTTParty.post(
        "#{api_base_url}/api/callback/registrations",
        headers: {
          "Authorization" => "Bearer #{installation_token}",
          "Content-Type" => "application/json",
        },
        body: { callback_registration: required_callback }.to_json
      )

      if (response.code == 200 || response.code == 201) && response["callback_registration"]["uuid"]
        installed_callback_ids << response["callback_registration"]["uuid"]
        Rails.logger.info(
          "[DropletInstalledJob] Successfully registered callback with UUID: " \
          "#{response['callback_registration']['uuid']}"
        )
      else
        Rails.logger.warn(
          "[DropletInstalledJob] Callback registered but no UUID returned for: " \
          "#{required_callback[:definition_name]} - Response: #{response.code}"
        )
      end
    rescue => e
      Rails.logger.error(
        "[DropletInstalledJob] Failed to register required callback " \
        "#{required_callback[:definition_name]}: #{e.message}"
      )
      Rails.logger.error(e.backtrace.join("\n"))
    end

    # Also register any additional active callbacks from database (optional/future use)
    active_callbacks = ::Callback.active
    active_callbacks.each do |callback|
      begin
        callback_attributes = {
          definition_name: callback.name,
          url: callback.url,
          timeout_in_seconds: callback.timeout_in_seconds,
          active: true,
        }

        response = HTTParty.post(
          "#{api_base_url}/api/callback/registrations",
          headers: {
            "Authorization" => "Bearer #{installation_token}",
            "Content-Type" => "application/json",
          },
          body: { callback_registration: callback_attributes }.to_json
        )

        if (response.code == 200 || response.code == 201) && response["callback_registration"]["uuid"]
          installed_callback_ids << response["callback_registration"]["uuid"]
        else
          Rails.logger.warn(
            "[DropletInstalledJob] Callback registered but no UUID returned for: #{callback.name} - " \
            "Response: #{response.code}"
          )
        end
      rescue => e
        Rails.logger.error(
          "[DropletInstalledJob] Failed to register callback #{callback.name}: #{e.message}"
        )
      end
    end

    if installed_callback_ids.any?
      company.update(installed_callback_ids: installed_callback_ids)
      Rails.logger.info(
        "[DropletInstalledJob] Updated company with #{installed_callback_ids.length} callback IDs"
      )
    end
  end
end
