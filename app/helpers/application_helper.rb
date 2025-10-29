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
end
