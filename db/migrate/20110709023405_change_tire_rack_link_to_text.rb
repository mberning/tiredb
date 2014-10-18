class ChangeTireRackLinkToText < ActiveRecord::Migration
  def self.up
    change_column :tires, :tire_rack_link, :text
  end

  def self.down
    change_column :tires, :tire_rack_link, :string
  end
end
