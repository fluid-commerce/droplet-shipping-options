require "test_helper"

describe DriAuthentication do
  fixtures(:companies)

  # Create a minimal test controller to test the concern
  class TestController < ApplicationController
    include DriAuthentication

    def index
      render json: { company_id: @company.id, message: "success" }
    end
  end

  before do
    @controller = TestController.new
    @request = ActionDispatch::TestRequest.create
    @response = ActionDispatch::TestResponse.new
    @company = companies(:acme)
  end

  describe "store_dri_in_session" do
    it "stores DRI in session when provided in params" do
      @request.params[:dri] = @company.droplet_installation_uuid
      @controller.stub :session, {} do
        @controller.send(:store_dri_in_session)
        _(@controller.session[:dri]).must_equal @company.droplet_installation_uuid
      end
    end

    it "renders error when no DRI in params or session" do
      @request.params[:dri] = nil
      session_stub = {}
      
      @controller.stub :session, session_stub do
        @controller.stub :params, @request.params do
          @controller.send(:store_dri_in_session)
        end
      end
      
      # The method should have rendered an error
      _(@response.status).wont_equal 200
    end

    it "uses existing session DRI when no param provided" do
      existing_dri = @company.droplet_installation_uuid
      @request.params[:dri] = nil
      session_stub = { dri: existing_dri }
      
      @controller.stub :session, session_stub do
        @controller.stub :params, @request.params do
          @controller.send(:store_dri_in_session)
        end
      end
      
      _(session_stub[:dri]).must_equal existing_dri
    end
  end

  describe "find_company_by_dri" do
    it "finds company when valid DRI is in session" do
      session_stub = { dri: @company.droplet_installation_uuid }
      
      @controller.stub :session, session_stub do
        @controller.stub :render, nil do
          @controller.send(:find_company_by_dri)
        end
      end
      
      _(@controller.instance_variable_get(:@company)).must_equal @company
    end

    it "handles missing company with proper error response" do
      invalid_dri = "dri_invalid123"
      session_stub = { dri: invalid_dri }
      rendered = false
      
      @controller.stub :session, session_stub do
        @controller.stub :render, ->(*args) { rendered = true; args } do
          @controller.send(:find_company_by_dri)
        end
      end
      
      _(rendered).must_equal true
    end

    it "handles uninstalled company with proper error response" do
      @company.update(uninstalled_at: Time.current)
      session_stub = { dri: @company.droplet_installation_uuid }
      rendered = false
      
      @controller.stub :session, session_stub do
        @controller.stub :render, ->(*args) { rendered = true; args } do
          @controller.send(:find_company_by_dri)
        end
      end
      
      _(rendered).must_equal true
    end

    it "handles inactive company with proper error response" do
      @company.update(active: false, uninstalled_at: nil)
      session_stub = { dri: @company.droplet_installation_uuid }
      rendered = false
      
      @controller.stub :session, session_stub do
        @controller.stub :render, ->(*args) { rendered = true; args } do
          @controller.send(:find_company_by_dri)
        end
      end
      
      _(rendered).must_equal true
    end
  end

  describe "render_dri_error" do
    it "renders JSON error with all provided fields" do
      rendered_json = nil
      rendered_status = nil
      
      @controller.stub :render, ->(json:, status:) { 
        rendered_json = json
        rendered_status = status
      } do
        @controller.send(:render_dri_error,
          message: "Test error",
          code: "TEST_ERROR",
          action_required: "test_action",
          details: "Test details",
          dri: "dri_test123"
        )
      end
      
      _(rendered_json[:error]).must_equal "Test error"
      _(rendered_json[:code]).must_equal "TEST_ERROR"
      _(rendered_json[:action_required]).must_equal "test_action"
      _(rendered_json[:details]).must_equal "Test details"
      _(rendered_json[:dri]).must_equal "dri_test123"
      _(rendered_status).must_equal :not_found
    end

    it "renders JSON error without optional fields" do
      rendered_json = nil
      
      @controller.stub :render, ->(json:, status:) { 
        rendered_json = json
      } do
        @controller.send(:render_dri_error,
          message: "Test error",
          code: "TEST_ERROR",
          action_required: "test_action"
        )
      end
      
      _(rendered_json[:error]).must_equal "Test error"
      _(rendered_json[:code]).must_equal "TEST_ERROR"
      _(rendered_json[:action_required]).must_equal "test_action"
      _(rendered_json.key?(:details)).must_equal false
      _(rendered_json.key?(:dri)).must_equal false
    end
  end
end

