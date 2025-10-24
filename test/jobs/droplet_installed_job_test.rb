require "test_helper"

describe DropletInstalledJob do
  describe "#perform" do
    it "creates a company from payload when company doesn't exist" do
      company_data = {
        "fluid_shop" => "unique-test-shop-123",
        "name" => "Test Shop",
        "fluid_company_id" => 12345,
        "droplet_uuid" => "test-uuid-123",
        "authentication_token" => "unique-test-auth-token",
        "webhook_verification_token" => "test-verify-token",
        "droplet_installation_uuid" => "test-installation-uuid-123",
      }

      payload = { "company" => company_data }

      _(-> { DropletInstalledJob.perform_now(payload) }).must_change "Company.count", +1

      # Find the created company
      company = Company.last

      # Verify company attributes
      _(company.fluid_shop).must_equal "unique-test-shop-123"
      _(company.name).must_equal "Test Shop"
      _(company.fluid_company_id).must_equal 12345
      _(company.company_droplet_uuid).must_equal "test-uuid-123"
      _(company.authentication_token).must_equal "unique-test-auth-token"
      _(company.webhook_verification_token).must_equal "test-verify-token"
      _(company.droplet_installation_uuid).must_equal "test-installation-uuid-123"
      _(company).must_be :active?
    end

    it "updates existing company when company already exists" do
      existing_company = Company.create!(
        fluid_shop: "unique-update-shop-456",
        name: "Old Name",
        fluid_company_id: 12345,
        company_droplet_uuid: "old-uuid",
        authentication_token: "unique-old-token",
        webhook_verification_token: "old-verify-token",
        active: false
      )

      company_data = {
        "fluid_shop" => "unique-update-shop-456",
        "name" => "Updated Shop",
        "fluid_company_id" => 12345,
        "droplet_uuid" => "new-uuid-123",
        "authentication_token" => "unique-new-auth-token",
        "webhook_verification_token" => "new-verify-token",
        "droplet_installation_uuid" => "new-installation-uuid-456",
      }

      payload = { "company" => company_data }

      _(-> { DropletInstalledJob.perform_now(payload) }).wont_change "Company.count"

      existing_company.reload
      _(existing_company.name).must_equal "Updated Shop"
      _(existing_company.company_droplet_uuid).must_equal "new-uuid-123"
      _(existing_company.authentication_token).must_equal "unique-new-auth-token"
      _(existing_company.webhook_verification_token).must_equal "new-verify-token"
      _(existing_company.droplet_installation_uuid).must_equal "new-installation-uuid-456"
      _(existing_company).must_be :active?
    end

    it "handles missing company droplet data" do
      # Empty payload
      payload = {}

      # Job should run without creating a company or raising errors
      _(-> { DropletInstalledJob.perform_now(payload) }).wont_change "Company.count"
    end

    it "handles invalid company data" do
      # Create invalid data (missing required fields)
      payload = {
        "company" => {
          "name" => "Invalid Company",
          # Missing required fields
        },
      }

      # Job should run without creating a company or raising errors
      _(-> { DropletInstalledJob.perform_now(payload) }).wont_change "Company.count"
    end

    it "registers callbacks when active callbacks exist" do
      # Create an active callback
      callback = ::Callback.create!(
        name: "test_callback",
        description: "Test callback",
        url: "https://example.com/callback",
        timeout_in_seconds: 10,
        active: true
      )

      company_data = {
        "fluid_shop" => "unique-callback-shop-789",
        "name" => "Callback Test Shop",
        "fluid_company_id" => 789,
        "droplet_uuid" => "callback-test-uuid",
        "authentication_token" => "unique-callback-auth-token",
        "webhook_verification_token" => "callback-verify-token",
        "droplet_installation_uuid" => "callback-installation-uuid",
      }

      payload = { "company" => company_data }

      # Job should run and create company even if callback registration fails
      _(-> { DropletInstalledJob.perform_now(payload) }).must_change "Company.count", +1

      # Check that the company was created
      company = Company.last
      _(company.fluid_shop).must_equal "unique-callback-shop-789"
      _(company.name).must_equal "Callback Test Shop"
    end

    it "handles callback registration errors gracefully" do
      # Create an active callback
      callback = ::Callback.create!(
        name: "test_callback",
        description: "Test callback",
        url: "https://example.com/callback",
        timeout_in_seconds: 10,
        active: true
      )

      company_data = {
        "fluid_shop" => "unique-error-shop-999",
        "name" => "Error Test Shop",
        "fluid_company_id" => 999,
        "droplet_uuid" => "error-test-uuid",
        "authentication_token" => "unique-error-auth-token",
        "webhook_verification_token" => "error-verify-token",
        "droplet_installation_uuid" => "error-installation-uuid",
      }

      payload = { "company" => company_data }

      # Job should run and create company even with callback errors
      _(-> { DropletInstalledJob.perform_now(payload) }).must_change "Company.count", +1

      # Check that the company was created
      company = Company.last
      _(company.fluid_shop).must_equal "unique-error-shop-999"
      _(company.name).must_equal "Error Test Shop"
    end

    it "handles no active callbacks" do
      # Ensure no active callbacks exist
      ::Callback.update_all(active: false)

      company_data = {
        "fluid_shop" => "unique-no-callback-shop-111",
        "name" => "No Callback Shop",
        "fluid_company_id" => 111,
        "droplet_uuid" => "no-callback-test-uuid",
        "authentication_token" => "unique-no-callback-auth-token",
        "webhook_verification_token" => "no-callback-verify-token",
        "droplet_installation_uuid" => "no-callback-installation-uuid",
      }

      payload = { "company" => company_data }

      # Job should run without any FluidClient calls
      _(-> { DropletInstalledJob.perform_now(payload) }).must_change "Company.count", +1

      # Check that the company was created without installed callback IDs
      company = Company.last
      _(company.installed_callback_ids).must_be_empty
    end
  end

  describe "reinstallation handling" do
    it "clears uninstalled_at when reinstalling a previously uninstalled droplet" do
      company = companies(:acme)
      company.update(uninstalled_at: Time.current)

      payload = {
        "resource" => "droplet",
        "event" => "installed",
        "company" => {
          "fluid_shop" => company.fluid_shop,
          "name" => company.name,
          "fluid_company_id" => company.fluid_company_id,
          "droplet_uuid" => company.company_droplet_uuid,
          "authentication_token" => company.authentication_token,
          "webhook_verification_token" => company.webhook_verification_token,
          "droplet_installation_uuid" => "dri_new_installation_uuid"
        }
      }

      job = DropletInstalledJob.new
      job.perform(payload)

      _(company.reload.uninstalled_at).must_be_nil
      _(company.reload.active).must_equal true
      _(company.reload.droplet_installation_uuid).must_equal "dri_new_installation_uuid"
    end

    it "updates droplet_installation_uuid when reinstalling" do
      company = companies(:acme)
      old_dri = company.droplet_installation_uuid
      new_dri = "dri_brand_new_installation"

      payload = {
        "resource" => "droplet",
        "event" => "installed",
        "company" => {
          "fluid_shop" => company.fluid_shop,
          "name" => company.name,
          "fluid_company_id" => company.fluid_company_id,
          "droplet_uuid" => company.company_droplet_uuid,
          "authentication_token" => company.authentication_token,
          "webhook_verification_token" => company.webhook_verification_token,
          "droplet_installation_uuid" => new_dri
        }
      }

      job = DropletInstalledJob.new
      job.perform(payload)

      _(company.reload.droplet_installation_uuid).must_equal new_dri
      _(company.reload.droplet_installation_uuid).wont_equal old_dri
    end

    it "logs reinstallation when DRI changes" do
      company = companies(:acme)
      old_dri = company.droplet_installation_uuid
      new_dri = "dri_reinstalled_uuid"

      payload = {
        "resource" => "droplet",
        "event" => "installed",
        "company" => {
          "fluid_shop" => company.fluid_shop,
          "name" => company.name,
          "fluid_company_id" => company.fluid_company_id,
          "droplet_uuid" => company.company_droplet_uuid,
          "authentication_token" => company.authentication_token,
          "webhook_verification_token" => company.webhook_verification_token,
          "droplet_installation_uuid" => new_dri
        }
      }

      log_output = StringIO.new
      original_logger = Rails.logger
      Rails.logger = Logger.new(log_output)

      job = DropletInstalledJob.new
      job.perform(payload)

      Rails.logger = original_logger

      log_content = log_output.string
      _(log_content).must_include "Reinstallation detected"
      _(log_content).must_include old_dri
      _(log_content).must_include new_dri
    end
  end
end

