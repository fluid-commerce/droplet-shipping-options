class CreateShippingOptions < ActiveRecord::Migration[8.0]
  def change
    create_table :shipping_options do |t|
      t.string :name
      t.integer :delivery_time
      t.decimal :starting_rate
      t.jsonb :countries
      t.string :status
      t.references :company, null: false, foreign_key: true

      t.timestamps
    end
  end
end
