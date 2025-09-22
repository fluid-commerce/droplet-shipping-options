class CreateRates < ActiveRecord::Migration[8.0]
  def change
    create_table :rates do |t|
      t.references :shipping_option, null: false, foreign_key: true
      t.integer :ship_method_id, null: false
      t.string :country, null: false
      t.string :region
      t.decimal :min_range_lbs, precision: 8, scale: 2, null: false
      t.decimal :max_range_lbs, precision: 8, scale: 2, null: false
      t.decimal :flat_rate, precision: 10, scale: 2, null: false
      t.decimal :min_charge, precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_index :rates, %i[shipping_option_id ship_method_id country region],
              name: 'index_rates_on_shipping_option_and_method_and_location'
    add_index :rates, %i[country region]
  end
end
