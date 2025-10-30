class IncreaseWeightRangePrecision < ActiveRecord::Migration[8.0]
  def change
    change_column :rates, :min_range_lbs, :decimal, precision: 8, scale: 4, null: false
    change_column :rates, :max_range_lbs, :decimal, precision: 8, scale: 4, null: false
  end
end
