class RenameTypeColumn < ActiveRecord::Migration
  def self.up
    rename_column :tires, :type, :tire_type
  end

  def self.down
    rename_column :tires, :tire_type, :type
  end
end
