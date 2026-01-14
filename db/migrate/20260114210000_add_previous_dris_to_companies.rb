class AddPreviousDrisToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :previous_dris, :jsonb, default: [], null: false
    add_index :companies, :previous_dris, using: :gin
  end
end
