class AddTireNotes < ActiveRecord::Migration
  def self.up
    add_column :tires, :manufacturer_link, :string
    add_column :tires, :model_link, :string
    add_column :tires, :notes, :string
  end

  def self.down
    remove_column :tires, :manufacturer_link
    remove_column :tires, :model_link
    remove_column :tires, :notes
  end
end
