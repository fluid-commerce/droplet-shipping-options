class CallbackCleanupService
  def initialize(company)
    @company = company
  end

  def call
    # Use stored callback IDs to ensure we delete exactly what we registered
    return unless @company.installed_callback_ids.present?

    # Skip API calls in test environment, but still clear the stored IDs
    unless Rails.env.test?
      client = FluidClient.new
      deleted_count = 0

      @company.installed_callback_ids.each do |callback_id|
        begin
          client.callback_registrations.delete(callback_id)
          deleted_count += 1
          Rails.logger.info("[CallbackCleanupService] Deleted callback: #{callback_id}")
        rescue => e
          # Log but don't fail - callback might already be deleted
          Rails.logger.warn(
            "[CallbackCleanupService] Could not delete callback #{callback_id}: #{e.message}"
          )
        end
      end

      Rails.logger.info(
        "[CallbackCleanupService] Deleted #{deleted_count} callback(s) for #{@company.fluid_shop}"
      )
    end

    # Always clear the stored IDs, even in test environment
    @company.update(installed_callback_ids: [])
  end
end
