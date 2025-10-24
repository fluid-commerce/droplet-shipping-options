require "test_helper"

describe Company do
  fixtures(:companies)
  fixtures(:events)

  describe "validations" do
    it "is valid with valid attributes" do
      company = companies(:acme)
      _(company).must_be :valid?
    end

    it "is not valid without a name" do
      company = companies(:acme).dup
      company.name = nil
      _(company).wont_be :valid?
    end

    it "is not valid without a fluid_shop" do
      company = companies(:acme).dup
      company.fluid_shop = nil
      _(company).wont_be :valid?
    end

    it "is not valid without an authentication_token" do
      company = companies(:acme).dup
      company.authentication_token = nil
      _(company).wont_be :valid?
    end

    it "is not valid without a fluid_company_id" do
      company = companies(:acme).dup
      company.fluid_company_id = nil
      _(company).wont_be :valid?
    end

    it "is not valid without a company_droplet_uuid" do
      company = companies(:acme).dup
      company.company_droplet_uuid = nil
      _(company).wont_be :valid?
    end

    it "requires unique authentication_token" do
      existing_company = companies(:acme)
      company = companies(:globex).dup
      company.authentication_token = existing_company.authentication_token

      _(company).wont_be :valid?
      _(company.errors[:authentication_token]).must_include "has already been taken"
    end
  end

  describe "associations" do
    it "has many events" do
      company = companies(:acme)
      _(company.events).must_include events(:order_completed)
      _(company.events).must_include events(:product_updated)
      _(company.events.count).must_equal 2
    end

    it "destroys associated events when destroyed" do
      company = companies(:acme)
      event_count = company.events.count
      assert_difference "Event.count", -event_count do
        company.destroy
      end
    end
  end

  describe "installation status methods" do
    it "installed? returns true when uninstalled_at is nil and active is true" do
      company = companies(:acme)
      company.update(uninstalled_at: nil, active: true)
      _(company.installed?).must_equal true
    end

    it "installed? returns false when uninstalled_at is present" do
      company = companies(:acme)
      company.update(uninstalled_at: Time.current, active: true)
      _(company.installed?).must_equal false
    end

    it "installed? returns false when active is false" do
      company = companies(:acme)
      company.update(uninstalled_at: nil, active: false)
      _(company.installed?).must_equal false
    end

    it "uninstalled? returns true when uninstalled_at is present" do
      company = companies(:acme)
      company.update(uninstalled_at: Time.current)
      _(company.uninstalled?).must_equal true
    end

    it "uninstalled? returns false when uninstalled_at is nil" do
      company = companies(:acme)
      company.update(uninstalled_at: nil)
      _(company.uninstalled?).must_equal false
    end
  end

  describe "scopes" do
    it "installed scope returns only companies without uninstalled_at" do
      companies(:acme).update(uninstalled_at: nil)
      companies(:globex).update(uninstalled_at: Time.current)

      installed_companies = Company.installed
      _(installed_companies).must_include companies(:acme)
      _(installed_companies).wont_include companies(:globex)
    end

    it "uninstalled scope returns only companies with uninstalled_at" do
      companies(:acme).update(uninstalled_at: nil)
      companies(:globex).update(uninstalled_at: Time.current)

      uninstalled_companies = Company.uninstalled
      _(uninstalled_companies).wont_include companies(:acme)
      _(uninstalled_companies).must_include companies(:globex)
    end
  end
end

