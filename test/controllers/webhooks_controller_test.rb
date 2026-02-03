require "test_helper"


describe WebhooksController do
  fixtures(:companies, :settings)

  let(:valid_droplet_uuid) { Setting.droplet.uuid }

  describe "droplet events" do
    describe "droplet_uuid validation" do
      it "rejects droplet installed event with wrong droplet_uuid" do
        company_data = {
          fluid_shop: "test-shop",
          name: "Test Company",
          fluid_company_id: 123456,
          droplet_uuid: "wrong-droplet-uuid",
          authentication_token: "secret-token-123",
          webhook_verification_token: "verify-token-456",
        }

        post webhook_url, params: {
          resource: "droplet",
          event: "installed",
          company: company_data,
        }, as: :json

        _(response.status).must_equal 401
        _(JSON.parse(response.body)["error"]).must_equal "Unauthorized - wrong droplet"
      end

      it "rejects droplet uninstalled event with wrong droplet_uuid" do
        company = companies(:acme)

        post webhook_url, params: {
          resource: "droplet",
          event: "uninstalled",
          company: {
            droplet_installation_uuid: company.droplet_installation_uuid,
            fluid_company_id: company.fluid_company_id,
            droplet_uuid: "wrong-droplet-uuid",
          },
        }, as: :json

        _(response.status).must_equal 401
        _(JSON.parse(response.body)["error"]).must_equal "Unauthorized - wrong droplet"
      end

      it "rejects droplet installed event with missing droplet_uuid" do
        company_data = {
          fluid_shop: "test-shop",
          name: "Test Company",
          fluid_company_id: 123456,
          # droplet_uuid intentionally omitted
          authentication_token: "secret-token-123",
          webhook_verification_token: "verify-token-456",
        }

        post webhook_url, params: {
          resource: "droplet",
          event: "installed",
          company: company_data,
        }, as: :json

        _(response.status).must_equal 401
        _(JSON.parse(response.body)["error"]).must_equal "Unauthorized - wrong droplet"
      end

      it "rejects droplet installed event with nil droplet_uuid" do
        company_data = {
          fluid_shop: "test-shop",
          name: "Test Company",
          fluid_company_id: 123456,
          droplet_uuid: nil,
          authentication_token: "secret-token-123",
          webhook_verification_token: "verify-token-456",
        }

        post webhook_url, params: {
          resource: "droplet",
          event: "installed",
          company: company_data,
        }, as: :json

        _(response.status).must_equal 401
        _(JSON.parse(response.body)["error"]).must_equal "Unauthorized - wrong droplet"
      end
    end

    it "handles droplet installed event with correct droplet_uuid" do
      company_data = {
        fluid_shop: "test-shop",
        name: "Test Company",
        fluid_company_id: 123456,
        droplet_uuid: valid_droplet_uuid,
        authentication_token: "secret-token-123",
        webhook_verification_token: "verify-token-456",
      }

      post webhook_url, params: {
        resource: "droplet",
        event: "installed",
        company: company_data,
      }, as: :json

      _(response.status).must_equal 202

      perform_enqueued_jobs

      company = Company.order(:created_at).last
      _(company.fluid_shop).must_equal "test-shop"
      _(company.name).must_equal "Test Company"
      _(company.fluid_company_id).must_equal 123456
      _(company.company_droplet_uuid).must_equal valid_droplet_uuid
      _(company).must_be :active?
    end

    it "handles droplet uninstalled event with correct droplet_uuid" do
      company = companies(:acme)

      post webhook_url, params: {
        resource: "droplet",
        event: "uninstalled",
        company: {
          droplet_installation_uuid: company.droplet_installation_uuid,
          fluid_company_id: company.fluid_company_id,
          droplet_uuid: valid_droplet_uuid,
        },
      }, as: :json

      _(response.status).must_equal 202

      perform_enqueued_jobs

      company.reload
      _(company.uninstalled_at).wont_be_nil
    end

    it "updates existing company on droplet installed event" do
      company = companies(:acme)

      post webhook_url, params: {
        resource: "droplet",
        event: "installed",
        company: {
          fluid_shop: company.fluid_shop,
          name: "Updated Company Name",
          fluid_company_id: company.fluid_company_id,
          droplet_uuid: valid_droplet_uuid,
          authentication_token: "updated-token-456",
          webhook_verification_token: company.webhook_verification_token,
        },
      }, as: :json

      _(response.status).must_equal 202

      perform_enqueued_jobs

      company.reload
      _(company.name).must_equal "Updated Company Name"
      _(company.company_droplet_uuid).must_equal valid_droplet_uuid
      _(company.authentication_token).must_equal "updated-token-456"
      _(company).must_be :active?
    end
  end

  describe "non-droplet events authentication" do
    it "rejects event when webhook verification token is invalid" do
      company = companies(:acme)
      post webhook_url, params: {
        resource: "order",
        event: "created",
        company: {
          droplet_installation_uuid: company.droplet_installation_uuid,
          fluid_company_id: company.fluid_company_id,
          webhook_verification_token: "invalid-token",
        },
      }, headers: { "AUTH_TOKEN" => "invalid-token" }, as: :json

      _(response.status).must_equal 401
      _(JSON.parse(response.body)["error"]).must_equal "Unauthorized"
    end

    it "rejects event when authentication token in header is invalid" do
      company = companies(:acme)
      post webhook_url, params: {
        resource: "order",
        event: "created",
        company: {
          droplet_installation_uuid: company.droplet_installation_uuid,
          fluid_company_id: company.fluid_company_id,
        },
      }, headers: { "AUTH_TOKEN" => "invalid-token" }, as: :json

      _(response.status).must_equal 401
      _(JSON.parse(response.body)["error"]).must_equal "Unauthorized"
    end

    it "returns 404 when company is not found" do
      webhook_auth_token = Setting.fluid_webhook.auth_token

      post webhook_url, params: {
        resource: "order",
        event: "created",
        company: {
          droplet_installation_uuid: "non-existent-uuid",
          fluid_company_id: 999999,
          webhook_verification_token: "any-token",
        },
      }, headers: { "AUTH_TOKEN" => webhook_auth_token }, as: :json

      _(response.status).must_equal 404
      _(JSON.parse(response.body)["error"]).must_equal "Company not found"
    end

    it "accepts global webhook auth token" do
      company = companies(:acme)
      webhook_auth_token = Setting.fluid_webhook.auth_token

      post webhook_url, params: {
        resource: "order",
        event: "created",
        company: {
          droplet_installation_uuid: company.droplet_installation_uuid,
          fluid_company_id: company.fluid_company_id,
        },
      }, headers: { "AUTH_TOKEN" => webhook_auth_token }, as: :json

      _(response.status).must_equal 204
    end

    it "accepts company webhook_verification_token in header" do
      company = companies(:acme)

      post webhook_url, params: {
        resource: "order",
        event: "created",
        company: {
          droplet_installation_uuid: company.droplet_installation_uuid,
          fluid_company_id: company.fluid_company_id,
        },
      }, headers: { "AUTH_TOKEN" => company.webhook_verification_token }, as: :json

      _(response.status).must_equal 204
    end
  end

  describe "unknown events" do
    it "handles unknown event types with no content" do
      company = companies(:acme)
      webhook_auth_token = Setting.fluid_webhook.auth_token

      post webhook_url, params: {
        resource: "unknown_resource",
        event: "unknown_event",
        company: {
          droplet_installation_uuid: company.droplet_installation_uuid,
          fluid_company_id: company.fluid_company_id,
          webhook_verification_token: company.webhook_verification_token,
        },
      }, headers: { "AUTH_TOKEN" => webhook_auth_token }, as: :json

      _(response.status).must_equal 204
    end
  end
end
