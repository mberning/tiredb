class Tire < ActiveRecord::Base
  validates_presence_of :manufacturer, :model, :width, :aspect_ratio, 
                        :wheel_diameter, :min_wheel_width, :max_wheel_width
                      
  validates_inclusion_of :asymmetrical, :in => [true, false]
  validates_inclusion_of :directional, :in => [true, false]
                        
  
  def tire_code
    "#{width}/#{aspect_ratio}R#{"%d" % wheel_diameter}"
  end
  
  def wheel_width_range
    "#{"%3.1f" % min_wheel_width} - #{"%3.1f" % max_wheel_width}" if (min_wheel_width && max_wheel_width)
  end
end
