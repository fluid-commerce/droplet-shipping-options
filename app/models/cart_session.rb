# frozen_string_literal: true

class CartSession < ApplicationRecord
  validates :cart_id, presence: true, uniqueness: true
end
