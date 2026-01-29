module ApplicationHelper
  include Pagy::Frontend

  def format_settings_values(values)
    return "" if values.blank?

    formatted_values = values.first(4).map do |key, value|
      "<span class='font-bold'>#{key}</span>: #{value}"
    end
    formatted_values << "..." if values.size > 4

    formatted_values.join(", ").html_safe
  end

  # Override url_for to automatically include DRI parameter when available
  def url_for(options = nil)
    url = super(options)
    return url unless url.is_a?(String)

    # Add DRI parameter if it exists in session and not already in URL
    if session[:dri].present? && !url.include?("dri=")
      separator = url.include?("?") ? "&" : "?"
      url = "#{url}#{separator}dri=#{CGI.escape(session[:dri])}"
    end

    url
  end

  def yoli_company?
    @company&.yoli?
  end

  def free_shipping_enabled?
    @company&.free_shipping_enabled?
  end
end
