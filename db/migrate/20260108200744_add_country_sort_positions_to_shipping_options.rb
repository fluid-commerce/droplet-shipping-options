class AddCountrySortPositionsToShippingOptions < ActiveRecord::Migration[8.0]
  def change
    add_column :shipping_options, :country_sort_positions, :jsonb, default: {}
    add_index :shipping_options, :country_sort_positions, using: :gin
  end
end
