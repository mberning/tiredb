class AddTireDiameter < ActiveRecord::Migration
  def self.up
    add_column(:tires, :tire_diameter, :decimal)
  end

  def self.down
    remove_column(:tires, :tire_diameter)
  end
end
