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
    CallbackCleanupService.new(company).call
  end
end
