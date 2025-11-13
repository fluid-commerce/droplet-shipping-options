class CallbackCleanupService
  def initialize(company)
    @company = company
  end

  def call
    # Skip API calls in test environment, but still clear the stored IDs
    unless Rails.env.test?
      client = FluidClient.new
      deleted_count = 0

      # First, delete callbacks tracked in the company record
      if @company.installed_callback_ids.present?
        @company.installed_callback_ids.each do |callback_id|
          begin
            client.callback_registrations.delete(callback_id)
            deleted_count += 1
            Rails.logger.info("[CallbackCleanupService] Deleted tracked callback: #{callback_id}")
          rescue => e
            # Log but don't fail - callback might already be deleted
            Rails.logger.warn(
              "[CallbackCleanupService] Could not delete tracked callback #{callback_id}: #{e.message}"
            )
          end
        end
      end

      # Second, fetch and delete any orphaned callbacks for this definition
      # This handles cases where callbacks were created but not tracked
      begin
        base_url = ENV.fetch("DROPLET_URL", "https://fluid-droplet-shipping-options-106074092699.europe-west1.run.app")
        expected_callback_url = "#{base_url}/callbacks/shipping_options"

        response = client.callback_registrations.get(definition_name: "update_cart_shipping")
        if response && response["callback_registrations"]
          response["callback_registrations"].each do |reg|
            callback_uuid = reg["uuid"]
            callback_url = reg["url"]

            # Skip if we already deleted this one
            next if @company.installed_callback_ids&.include?(callback_uuid)

            # IMPORTANT: Only delete callbacks that point to OUR app's URL
            # This prevents accidentally deleting callbacks from other apps
            unless callback_url == expected_callback_url
              Rails.logger.info(
                "[CallbackCleanupService] Skipping callback #{callback_uuid} - " \
                "URL mismatch (ours: #{expected_callback_url}, theirs: #{callback_url})"
              )
              next
            end

            begin
              client.callback_registrations.delete(callback_uuid)
              deleted_count += 1
              Rails.logger.info(
                "[CallbackCleanupService] Deleted orphaned callback: #{callback_uuid}"
              )
            rescue => e
              Rails.logger.warn(
                "[CallbackCleanupService] Could not delete orphaned callback #{callback_uuid}: #{e.message}"
              )
            end
          end
        end
      rescue => e
        Rails.logger.warn(
          "[CallbackCleanupService] Could not fetch existing callbacks: #{e.message}"
        )
      end

      Rails.logger.info(
        "[CallbackCleanupService] Deleted #{deleted_count} callback(s) for #{@company.fluid_shop}"
      )
    end

    # Always clear the stored IDs, even in test environment
    @company.update(installed_callback_ids: [])
  end
end
