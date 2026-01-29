# frozen_string_literal: true

class CartSessionService
  CACHE_TTL = 30.minutes

  def initialize(cart_id)
    @cart_id = cart_id
  end

  # Guarda que un usuario está logueado en este cart
  def store_user_login(user_id, email: nil)
    Rails.cache.write(user_key, user_id, expires_in: CACHE_TTL)
    Rails.cache.write(email_key, email, expires_in: CACHE_TTL) if email

    Rails.logger.info(
      "[CartSession] User #{user_id} logged in for cart #{@cart_id}"
    )
  end

  # Guarda si el usuario tiene suscripción activa
  def store_subscription_status(has_subscription)
    Rails.cache.write(
      subscription_key,
      has_subscription,
      expires_in: CACHE_TTL
    )

    Rails.logger.info(
      "[CartSession] Subscription status for cart #{@cart_id}: #{has_subscription}"
    )
  end

  # Obtiene el user_id del cart
  def user_id
    Rails.cache.read(user_key)
  end

  # Verifica si tiene suscripción activa
  def has_active_subscription?
    Rails.cache.read(subscription_key) == true
  end

  # Limpia la sesión del cart
  def clear
    Rails.cache.delete(user_key)
    Rails.cache.delete(email_key)
    Rails.cache.delete(subscription_key)
  end

  # Verifica si hay un usuario logueado
  def user_logged_in?
    user_id.present?
  end

  private

  def user_key
    "cart:#{@cart_id}:user_id"
  end

  def email_key
    "cart:#{@cart_id}:email"
  end

  def subscription_key
    "cart:#{@cart_id}:has_subscription"
  end
end
