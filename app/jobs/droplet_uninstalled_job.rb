class DropletUninstalledJob < WebhookEventJob
  queue_as :default

  def process_webhook
    validate_payload_keys("company")
    company = get_company

    if company.present?
      Rails.logger.info(
        "[DropletUninstalledJob] Uninstalling droplet for #{company.fluid_shop}. " \
        "DRI: #{company.droplet_installation_uuid}"
      )
      
      delete_installed_callbacks(company)

      company.update(uninstalled_at: Time.current)
      
      Rails.logger.info(
        "[DropletUninstalledJob] Note: Users with existing sessions using DRI #{company.droplet_installation_uuid} " \
        "will receive an error message on next request and need to reinstall the droplet."
      )
    else
      Rails.logger.warn("[DropletUninstalledJob] Company not found for payload: #{get_payload.inspect}")
    end
  end

private

  def delete_installed_callbacks(company)
    return unless company.installed_callback_ids.present?

    client = FluidClient.new

    company.installed_callback_ids.each do |callback_id|
      begin
        client.callback_registrations.delete(callback_id)
      rescue => e
        Rails.logger.error("[DropletUninstalledJob] Failed to delete callback #{callback_id}: #{e.message}")
      end
    end

    company.update(installed_callback_ids: [])
  end
end
