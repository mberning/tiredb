# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20110730032408) do

  create_table "tires", :force => true do |t|
    t.string   "manufacturer"
    t.string   "model"
    t.string   "sku"
    t.integer  "width"
    t.integer  "aspect_ratio"
    t.decimal  "wheel_diameter"
    t.boolean  "asymmetrical"
    t.boolean  "directional"
    t.integer  "treadwear"
    t.decimal  "min_wheel_width"
    t.decimal  "max_wheel_width"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.decimal  "weight"
    t.decimal  "tire_diameter"
    t.string   "tire_type"
    t.text     "tire_rack_link"
    t.string   "manufacturer_link"
    t.string   "model_link"
    t.string   "notes"
  end

  add_index "tires", ["manufacturer", "width", "aspect_ratio", "wheel_diameter", "tire_diameter", "tire_type", "weight", "directional", "asymmetrical"], :name => "index_hardcore_search"
  add_index "tires", ["manufacturer", "width", "wheel_diameter", "tire_diameter", "tire_type", "weight", "directional", "asymmetrical"], :name => "index_standard_search"
  add_index "tires", ["manufacturer", "width", "wheel_diameter", "tire_type", "weight", "directional", "asymmetrical"], :name => "index_staggered_search"
  add_index "tires", ["wheel_diameter", "tire_diameter", "weight", "width"], :name => "index_default_search"

end
