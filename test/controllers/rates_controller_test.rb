require "test_helper"

describe RatesController do
  it "gets index" do
    get rates_index_url
    must_respond_with :success
  end

  it "gets show" do
    get rates_show_url
    must_respond_with :success
  end

  it "gets new" do
    get rates_new_url
    must_respond_with :success
  end

  it "gets create" do
    get rates_create_url
    must_respond_with :success
  end

  it "gets edit" do
    get rates_edit_url
    must_respond_with :success
  end

  it "gets update" do
    get rates_update_url
    must_respond_with :success
  end

  it "gets destroy" do
    get rates_destroy_url
    must_respond_with :success
  end
end
