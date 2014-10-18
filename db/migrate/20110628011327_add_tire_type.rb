class AddTireType < ActiveRecord::Migration
  def self.up
    add_column :tires, :type, :string
    add_column :tires, :tire_rack_link, :string
  end

  def self.down
    remove_column :tires, :type
    remove_column :tires, :tire_rack_link
  end
end
