class CallbackCleanupService
  CALLBACK_PATH = "/callbacks/shipping_options".freeze
  DEFAULT_DROPLET_URLS = [
    "https://fluid-droplet-shipping-options-295375388381.us-south1.run.app",
    "https://fluid-droplet-shipping-options-106074092699.europe-west1.run.app",
    "https://fluid-droplet-shipping-options-3h47nfle6q-ew.a.run.app",
  ].freeze

  def self.own_callback_urls
    urls = [ ENV.fetch("DROPLET_URL", DEFAULT_DROPLET_URLS.first) ] + DEFAULT_DROPLET_URLS
    urls.uniq.map { |url| "#{url}#{CALLBACK_PATH}" }
  end

  def initialize(company)
    @company = company
  end

  def call
    # Skip API calls in test environment, but still clear the stored IDs
    unless Rails.env.test?
      # CRITICAL: Must use the installation token, not the company token
      # Callbacks are registered per-droplet-installation, so we need the
      # authentication_token (droplet installation token) to see/delete them
      installation_token = @company.authentication_token
      unless installation_token
        Rails.logger.warn(
          "[CallbackCleanupService] No installation token for #{@company.fluid_shop}, " \
          "skipping API cleanup"
        )
        @company.update(installed_callback_ids: [])
        return
      end

      deleted_count = 0
      base_url = Setting.fluid_api.base_url

      # First, delete callbacks tracked in the company record
      if @company.installed_callback_ids.present?
        @company.installed_callback_ids.each do |callback_id|
          begin
            response = HTTParty.delete(
              "#{base_url}/api/callback/registrations/#{callback_id}",
              headers: {
                "Authorization" => "Bearer #{installation_token}",
                "Content-Type" => "application/json",
              }
            )
            if response.code == 200 || response.code == 204
              deleted_count += 1
              Rails.logger.info("[CallbackCleanupService] Deleted tracked callback: #{callback_id}")
            else
              Rails.logger.warn(
                "[CallbackCleanupService] Could not delete tracked callback #{callback_id}: " \
                "#{response.code} - #{response.body}"
              )
            end
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
        expected_callback_urls = self.class.own_callback_urls

        # Fetch all callback registrations for this definition
        list_response = HTTParty.get(
          "#{base_url}/api/callback/registrations?definition_name=update_cart_shipping",
          headers: {
            "Authorization" => "Bearer #{installation_token}",
            "Content-Type" => "application/json",
          }
        )

        if list_response.code == 200 && list_response["callback_registrations"]
          list_response["callback_registrations"].each do |reg|
            callback_uuid = reg["uuid"]
            callback_url = reg["url"]

            # Skip if we already deleted this one
            next if @company.installed_callback_ids&.include?(callback_uuid)

            # IMPORTANT: Only delete callbacks that point to OUR app's URL
            # This prevents accidentally deleting callbacks from other apps
            unless expected_callback_urls.include?(callback_url)
              Rails.logger.info(
                "[CallbackCleanupService] Skipping callback #{callback_uuid} - " \
                "URL mismatch (ours: #{expected_callback_urls.join(", ")}, theirs: #{callback_url})"
              )
              next
            end

            begin
              delete_response = HTTParty.delete(
                "#{base_url}/api/callback/registrations/#{callback_uuid}",
                headers: {
                  "Authorization" => "Bearer #{installation_token}",
                  "Content-Type" => "application/json",
                }
              )
              if delete_response.code == 200 || delete_response.code == 204
                deleted_count += 1
                Rails.logger.info(
                  "[CallbackCleanupService] Deleted orphaned callback: #{callback_uuid}"
                )
              else
                Rails.logger.warn(
                  "[CallbackCleanupService] Could not delete orphaned callback #{callback_uuid}: " \
                  "#{delete_response.code} - #{delete_response.body}"
                )
              end
            rescue => e
              Rails.logger.warn(
                "[CallbackCleanupService] Could not delete orphaned callback #{callback_uuid}: #{e.message}"
              )
            end
          end
        else
          Rails.logger.info(
            "[CallbackCleanupService] No callbacks found or error fetching: #{list_response.code}"
          )
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
