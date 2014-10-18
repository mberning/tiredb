class AddIndexes < ActiveRecord::Migration
  def self.up
    add_index(:tires, [:manufacturer, :wheel_diameter, :tire_diameter, :tire_type, :weight, :asymmetrical, :directional, :width, :aspect_ratio], :name => 'index_standard_search')
    add_index(:tires, [:manufacturer, :wheel_diameter, :tire_diameter, :tire_type, :weight, :asymmetrical, :directional, :width], :name => 'index_staggered_search')
  end

  def self.down
    remove_index(:tires, :name => 'index_standard_search')
    remove_index(:tires, :name => 'index_staggered_search')
  end
end
