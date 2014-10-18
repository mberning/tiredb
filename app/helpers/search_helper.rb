module SearchHelper
  def min_tire_width
    145
  end
  
  def max_tire_width
    395
  end

  def default_min_tire_width 
    225
  end
  
  def default_max_tire_width 
    295
  end
  
  def default_min_rear_tire_width 
    255
  end
  
  def default_max_rear_tire_width 
    285
  end
  
  def default_min_front_tire_width 
    215
  end
  
  def default_max_front_tire_width 
    245
  end
  
  def min_tire_ar
    15
  end
  
  def max_tire_ar
    85
  end

  def default_min_tire_ar 
    20
  end
  
  def default_max_tire_ar 
    65
  end
  
  def min_wheel_diameter
    13
  end
  
  def max_wheel_diameter
    26
  end
  
  def default_wheel_diameter
    17
  end
  
  def min_wheel_width
    4.5
  end
  
  def max_wheel_width
    13.5
  end
  
  def default_wheel_width
    8
  end
  
  def default_rear_wheel_diameter
    19
  end
  
  def default_front_wheel_diameter
    18
  end

  def default_min_wheel_diameter
    16
  end
  
  def default_max_wheel_diameter
    19
  end
  
  def min_tire_diameter
    19
  end
  
  def max_tire_diameter
    34
  end

  def default_min_tire_diameter
    20
  end
  
  def default_max_tire_diameter
    32
  end
  
  def min_tire_weight
    10
  end
  
  def max_tire_weight
    50
  end
  
  def default_min_tire_weight
    15
  end
  
  def default_max_tire_weight
    40
  end
  
  def default_min_tire_treadwear
    10
  end
  
  def default_max_tire_treadwear
    400
  end
  
  def asymmetrical
    [['Yes', true], ['No', false], ['Any', 'any']]
  end
  
  def default_asymmetrical
    'any'
  end
  
  def directional
    [['Yes', true], ['No', false], ['Any', 'any']]
  end
  
  def default_directional
    'any'
  end
  
  def available_sorts
    [
      ['Brand','manufacturer'],
      ['Model','model'],
      ['Width','width'],
      ['Wheel Diameter','wheel_diameter'],
      ['Tire Diameter', 'tire_diameter'],
      ['Profile','aspect_ratio'],
      ['Tire Type', 'tire_type'],
      ['Weight', 'weight']
    ]
  end
  
  def available_orders
    [
      ['Ascending', 'asc'],
      ['Descending', 'desc']
    ]
  end
  
  def sort_icon(field)
    # if the user has submitted a search figure out which kind of arrow to show in the header row
    if params[:sorts]
      index = params[:sorts].index(field)
      if index
        if params[:orders][index] == 'asc'
          return '<span class="sprite sprite-sort_asc"></span>'
        else
          return '<span class="sprite sprite-sort_desc"></span>'
        end
      end
      return '<span class="sprite sprite-sort"></span>'
    # else we need to display the default arrows
    else
      if ['tire_type', 'manufacturer', 'model', 'wheel_diameter', 'width'].include? field
        return '<span class="sprite sprite-sort_asc"></span>'
      else
        return '<span class="sprite sprite-sort"></span>'
      end
    end
  end
  
  def translate_tire_type(type)
    {
      '0dotr' => 'DOT R', 
      '1hps' => 'Extreme Summer', 
      '2s' => 'HP Summer', 
      '3hpa' => 'HP All Season',
      '4a' => 'All Season',
      '5hpw' => 'HP Winter', 
      '6w' => 'Winter Ice/Snow'
    }[type] 
  end
 
end
