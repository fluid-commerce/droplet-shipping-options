class RemoveShipMethodIdFromRates < ActiveRecord::Migration[8.0]
  def change
    # Eliminar el índice que incluye ship_method_id
    remove_index :rates, name: 'index_rates_on_shipping_option_and_method_and_location'
    
    # Eliminar la columna ship_method_id
    remove_column :rates, :ship_method_id, :integer
    
    # Crear nuevo índice sin ship_method_id
    add_index :rates, [:shipping_option_id, :country, :region], 
              name: 'index_rates_on_shipping_option_and_location'
  end
end
