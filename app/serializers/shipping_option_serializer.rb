class ShippingOptionSerializer < ActiveModel::Serializer
  attributes :shipping_total, :shipping_title, :shipping_delivery_time_estimate

  def shipping_total
    object.starting_rate.to_f.to_s
  end

  def shipping_title
    object.name
  end

  def shipping_delivery_time_estimate
    case object.delivery_time
    when 0
      "Available same day"
    when 1
      "1 day"
    else
      "#{object.delivery_time} days"
    end
  end
end
