# frozen_string_literal: true

class CartSessionService
  def initialize(cart_id)
    @cart_id = cart_id
  end

  def store_login(email, has_subscription:)
    record = find_or_initialize
    record.update!(email: email, has_active_subscription: has_subscription)
  end

  def has_active_subscription?
    find_record&.has_active_subscription == true
  end

  def cached_email
    find_record&.email
  end

  def clear_all
    find_record&.destroy
  end

private

  def find_record
    @record ||= CartSession.find_by(cart_id: @cart_id)
  end

  def find_or_initialize
    CartSession.find_or_initialize_by(cart_id: @cart_id)
  end
end
