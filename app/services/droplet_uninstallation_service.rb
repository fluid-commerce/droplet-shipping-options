class DropletUninstallationService
  def initialize(payload)
    @payload = payload
  end

  def call
    validate_payload
    company = find_company

    if company.present?
      uninstall_droplet(company)
      { success: true, company: company }
    else
      Rails.logger.warn("[DropletUninstallationService] Company not found for payload")
      { success: false, error: "Company not found" }
    end
  rescue => e
    Rails.logger.error("[DropletUninstallationService] Error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    { success: false, error: e.message }
  end

private

  def validate_payload
    unless @payload["company"].present?
      raise ArgumentError, "Missing required payload key: company"
    end
  end

  def find_company
    uuid = @payload.dig("company", "company_droplet_uuid")
    fluid_company_id = @payload.dig("company", "fluid_company_id")

    Company.find_by(company_droplet_uuid: uuid) || Company.find_by(fluid_company_id: fluid_company_id)
  end

  def uninstall_droplet(company)
    Rails.logger.info(
      "[DropletUninstallationService] Uninstalling droplet for #{company.fluid_shop}. " \
      "DRI: #{company.droplet_installation_uuid}"
    )

    delete_installed_callbacks(company)
    company.update(uninstalled_at: Time.current)

    Rails.logger.info(
      "[DropletUninstallationService] Note: Users with existing sessions using " \
      "DRI #{company.droplet_installation_uuid} will receive an error message on next request."
    )
  end

  def delete_installed_callbacks(company)
    # Skip callback deletion in test environment
    return if Rails.env.test?

    # Use stored callback IDs to ensure we delete exactly what we registered
    return unless company.installed_callback_ids.present?

    client = FluidClient.new
    deleted_count = 0

    company.installed_callback_ids.each do |callback_id|
      begin
        client.callback_registrations.delete(callback_id)
        deleted_count += 1
        Rails.logger.info("[DropletUninstallationService] Deleted callback: #{callback_id}")
      rescue => e
        Rails.logger.error(
          "[DropletUninstallationService] Failed to delete callback #{callback_id}: #{e.message}"
        )
      end
    end

    Rails.logger.info(
      "[DropletUninstallationService] Deleted #{deleted_count} callback(s)"
    )

    company.update(installed_callback_ids: [])
  end
end
