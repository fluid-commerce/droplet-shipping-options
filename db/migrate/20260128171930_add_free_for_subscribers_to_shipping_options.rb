class AddFreeForSubscribersToShippingOptions < ActiveRecord::Migration[8.0]
  def change
    add_column :shipping_options, :free_for_subscribers, :boolean, default: false, null: false
    add_index :shipping_options, :free_for_subscribers
  end
end
