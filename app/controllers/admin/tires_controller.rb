class Admin::TiresController < Admin::AdminController
  def stats
    @brands = Tire.find_by_sql('select distinct manufacturer from tires order by 1 asc')
    @types = Tire.find_by_sql('select distinct tire_type from tires order by 1 asc')
    
    @tires = {}
    
    @types.each do |type|
      @tires[type.tire_type] = {}
      @brands.each do |brand|
        models = Tire.find_by_sql(['select distinct model from tires where tire_type = ? and manufacturer = ? order by 1 asc', type.tire_type, brand.manufacturer])
        @tires[type.tire_type][brand.manufacturer] = models.collect { |m| m.model }
      end
    end
  end
end
