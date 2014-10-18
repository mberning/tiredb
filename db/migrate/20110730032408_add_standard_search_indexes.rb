class AddStandardSearchIndexes < ActiveRecord::Migration
  def self.up
    remove_index(:tires, :name => 'index_standard_search')
    remove_index(:tires, :name => 'index_staggered_search')
    
    add_index(:tires, [:wheel_diameter, :tire_diameter, :weight, :width], :name => 'index_default_search')
    add_index(:tires, [:manufacturer, :width, :wheel_diameter, :tire_diameter, :tire_type, :weight, :directional, :asymmetrical], :name => 'index_standard_search')
    add_index(:tires, [:manufacturer, :width, :wheel_diameter, :tire_type, :weight, :directional, :asymmetrical], :name => 'index_staggered_search')
    add_index(:tires, [:manufacturer, :width, :aspect_ratio, :wheel_diameter, :tire_diameter, :tire_type, :weight, :directional, :asymmetrical], :name => 'index_hardcore_search')
  end

  def self.down
    remove_index(:tires, :name => 'index_default_search')
    remove_index(:tires, :name => 'index_standard_search')
    remove_index(:tires, :name => 'index_staggered_search')
    remove_index(:tires, :name => 'index_hardcore_search')
    
    add_index(:tires, [:manufacturer, :wheel_diameter, :tire_diameter, :tire_type, :weight, :asymmetrical, :directional, :width, :aspect_ratio], :name => 'index_standard_search')
    add_index(:tires, [:manufacturer, :wheel_diameter, :tire_diameter, :tire_type, :weight, :asymmetrical, :directional, :width], :name => 'index_staggered_search')
  end
end
