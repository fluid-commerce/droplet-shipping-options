# frozen_string_literal: true

# Prevent TinyTds from appending @hostname to the username when azure: true.
# Azure mode enables encryption (required for Exigo sandbox), but the default
# username mangling breaks authentication for non-Azure-hosted SQL Servers
# like sandbox.bi.exigo.com.
TinyTds::Client.class_eval do
  private

  alias_method :original_parse_username, :parse_username

  def parse_username(opts)
    opts[:username]
  end
end
