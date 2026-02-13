class CreateCartSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :cart_sessions do |t|
      t.integer :cart_id, null: false
      t.string :email
      t.boolean :has_active_subscription, default: false, null: false

      t.timestamps
    end
    add_index :cart_sessions, :cart_id, unique: true
  end
end
