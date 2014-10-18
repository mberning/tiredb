class CreateTires < ActiveRecord::Migration
  def self.up
    create_table :tires do |t|
      t.string :manufacturer
      t.string :model
      t.string :sku
      t.integer :width
      t.integer :aspect_ratio
      t.decimal :wheel_diameter
      t.boolean :asymmetrical
      t.boolean :directional
      t.integer :treadwear
      t.decimal :min_wheel_width
      t.decimal :max_wheel_width

      t.timestamps
    end
  end

  def self.down
    drop_table :tires
  end
end
