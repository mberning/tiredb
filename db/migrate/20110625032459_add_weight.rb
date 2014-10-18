class AddWeight < ActiveRecord::Migration
  def self.up
    add_column(:tires, :weight, :decimal)
  end

  def self.down
    remove_column(:tires, :weight)
  end
end
