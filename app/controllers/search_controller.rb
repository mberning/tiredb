class SearchController < ApplicationController    
  include SearchHelper
  
  def index
    width = Range.new(default_min_tire_width, default_max_tire_width)
    wheel_diameter = default_wheel_diameter
    tire_diameter = Range.new(default_min_tire_diameter, default_max_tire_diameter)
    tire_weight = Range.new(default_min_tire_weight, default_max_tire_weight)
    
    @tires = Tire.where(
      :width => width, 
      :wheel_diameter => wheel_diameter, 
      :tire_diameter => tire_diameter, 
      :weight => tire_weight
    ).order('tire_type asc,manufacturer asc, model asc, wheel_diameter asc, width asc').all
  end
  
  def standard_search
    brands = params[:brands]
    width = Range.new(params[:min_tire_width], params[:max_tire_width])
    wheel_diameter = params[:wheel_diameter]
    tire_diameter = Range.new(params[:min_tire_diameter], params[:max_tire_diameter])
    types = params[:tire_types]
    tire_weight = Range.new(params[:min_tire_weight], params[:max_tire_weight])
    asymmetrical = params[:asymmetrical] == 'any' ? [true, false, nil] : params[:asymmetrical]
    directional = params[:directional] == 'any' ? [true, false, nil] : params[:directional]

    sort_orders = []

    params[:sorts].each_with_index { |sort,index|
      sort_orders << "#{params[:sorts][index]} #{params[:orders][index]}"
    }

    @tires = Tire.where(
      :manufacturer => brands, 
      :width => width, 
      :wheel_diameter => wheel_diameter, 
      :tire_diameter => tire_diameter, 
      :tire_type => types, 
      :weight => tire_weight,
      :asymmetrical => asymmetrical, 
      :directional => directional
    ).order(sort_orders.join(','))
    
    @tires
    
    render :partial => 'partials/tire_results_standard'
  end
  
  def wheel_search
    brands = params[:brands]
    min_wheel_width = Range.new("0", params[:wheel_width])
    max_wheel_width = Range.new(params[:wheel_width], "100")
    wheel_diameter = params[:wheel_diameter]
    tire_diameter = Range.new(params[:min_tire_diameter], params[:max_tire_diameter])
    types = params[:tire_types]
    tire_weight = Range.new(params[:min_tire_weight], params[:max_tire_weight])
    asymmetrical = params[:asymmetrical] == 'any' ? [true, false, nil] : params[:asymmetrical]
    directional = params[:directional] == 'any' ? [true, false, nil] : params[:directional]

    sort_orders = []

    params[:sorts].each_with_index { |sort,index|
      sort_orders << "#{params[:sorts][index]} #{params[:orders][index]}"
    }

    @tires = Tire.where(
      :manufacturer => brands, 
      :min_wheel_width => min_wheel_width,
      :max_wheel_width => max_wheel_width,
      :wheel_diameter => wheel_diameter, 
      :tire_diameter => tire_diameter, 
      :tire_type => types, 
      :weight => tire_weight,
      :asymmetrical => asymmetrical, 
      :directional => directional
    ).order(sort_orders.join(','))
    
    @tires
    
    render :partial => 'partials/tire_results_standard'
  end
  
  def staggered_search
    brands = params[:brands]
    rear_width = Range.new(params[:min_rear_tire_width], params[:max_rear_tire_width])
    front_width = Range.new(params[:min_front_tire_width], params[:max_front_tire_width])
    rear_wheel_diameter = params[:rear_wheel_diameter]
    front_wheel_diameter = params[:front_wheel_diameter]
    types = params[:tire_types]
    tire_weight = Range.new(params[:min_tire_weight], params[:max_tire_weight])
    asymmetrical = params[:asymmetrical] == 'any' ? [true, false, nil] : params[:asymmetrical]
    directional = params[:directional] == 'any' ? [true, false, nil] : params[:directional]

    sort_orders = []

    params[:sorts].each_with_index { |sort,index|
      sort_orders << "#{params[:sorts][index]} #{params[:orders][index]}"
    }
    
    @tires = []

    rear_tires = Tire.where(
      :manufacturer => brands, 
      :width => rear_width, 
      :wheel_diameter => rear_wheel_diameter, 
      :tire_type => types, 
      :weight => tire_weight,
      :asymmetrical => asymmetrical, 
      :directional => directional
    ).order(sort_orders.join(','))

    rear_tires.each do |tire|
      front_tires = Tire.where(
        :manufacturer => tire.manufacturer,
        :model => tire.model,
        :width => front_width, 
        :wheel_diameter => front_wheel_diameter, 
        :tire_diameter => Range.new((tire.tire_diameter - 0.2), (tire.tire_diameter + 0.2)),
        :tire_type => types, 
        :weight => tire_weight,
        :asymmetrical => asymmetrical, 
        :directional => directional
      ).order(sort_orders.join(','))

      @tires << [tire, front_tires] if !front_tires.blank?
      
    end
    
    render :partial => 'partials/tire_results_staggered'
  end
  
  def hardcore_search
    brands = params[:brands]
    width = Range.new(params[:min_tire_width], params[:max_tire_width])
    ar = Range.new(params[:min_ar], params[:max_ar])
    wheel_diameter = Range.new(params[:min_wheel_diameter], params[:max_wheel_diameter])
    tire_diameter = Range.new(params[:min_tire_diameter], params[:max_tire_diameter])
    types = params[:tire_types]
    tire_weight = Range.new(params[:min_tire_weight], params[:max_tire_weight])
    asymmetrical = params[:asymmetrical] == 'any' ? [true, false, nil] : params[:asymmetrical]
    directional = params[:directional] == 'any' ? [true, false, nil] : params[:directional]

    sort_orders = []

    params[:sorts].each_with_index { |sort,index|
      sort_orders << "#{params[:sorts][index]} #{params[:orders][index]}"
    }

    @tires = Tire.where(
      :manufacturer => brands, 
      :width => width,
      :aspect_ratio => ar,
      :wheel_diameter => wheel_diameter, 
      :tire_diameter => tire_diameter, 
      :tire_type => types, 
      :weight => tire_weight,
      :asymmetrical => asymmetrical, 
      :directional => directional
    ).order(sort_orders.join(','))
    
    @tires
    
    render :partial => 'partials/tire_results_standard'
  end
  
  def standard_search_form
    render :partial => '/partials/tire_search_form_standard'
  end
  
  def wheel_search_form
    render :partial => '/partials/tire_search_form_wheel'
  end
  
  def staggered_search_form
    render :partial => '/partials/tire_search_form_staggered'
  end
  
  def hardcore_search_form
    render :partial => '/partials/tire_search_form_hardcore'
  end

end
