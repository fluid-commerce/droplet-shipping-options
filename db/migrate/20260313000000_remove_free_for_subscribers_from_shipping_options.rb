class RemoveFreeForSubscribersFromShippingOptions < ActiveRecord::Migration[8.0]
  def change
    remove_column :shipping_options, :free_for_subscribers, :boolean, default: false, null: false
  end
end
