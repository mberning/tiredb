module TireData

  def self.load_tire_data
    ActiveRecord::Base.transaction do
      Tire.delete_all

      @tires.each_pair do |manufacturer, models|
        models.each_pair do |model, details|
          asymmetrical = details['asymmetrical']
          directional = details['directional']
          treadwear = details['treadwear']
          tire_type = details['tire_type']
          tire_rack_link = details['tire_rack_link']
          manufacturer_link = details['manufacturer_link']
          model_link = details['model_link']

          if details['sizes'].class == Hash
            details['sizes'].each_pair do |wheel_diam, sizes|
              sizes.each do |size|
                size[:manufacturer] = manufacturer
                size[:model] = model
                size[:wheel_diameter] = wheel_diam
                size[:asymmetrical] = asymmetrical if asymmetrical != nil
                size[:directional] = directional if directional != nil
                size[:treadwear] = treadwear
                size[:tire_type] = tire_type
                size[:tire_rack_link] = tire_rack_link
                size[:manufacturer_link] = manufacturer_link
                size[:model_link] = model_link

                Tire.create(size)
              end
            end
          elsif details['sizes'].class == String
            File.open(details['sizes'], 'r') do |contents|
              contents.each_line do |line|
                fields = line.split(",")
                fields.each_index { |index| fields[index] = nil if fields[index].blank? }
                
                size = {}
                
                size[:width] = fields[0]
                size[:aspect_ratio] = fields[1]
                size[:wheel_diameter] = fields[2]
                size[:weight] = fields[7]
                size[:tire_diameter] = fields[13]
                size[:min_wheel_width] = fields[8]
                size[:max_wheel_width] = fields[9]
                
                size[:manufacturer] = manufacturer
                size[:model] = model
                size[:asymmetrical] = asymmetrical if asymmetrical != nil
                size[:directional] = directional if directional != nil
                size[:treadwear] = treadwear
                size[:tire_type] = tire_type
                size[:tire_rack_link] = tire_rack_link
                size[:manufacturer_link] = manufacturer_link
                size[:model_link] = model_link
                
                tire = Tire.new(size)
                
                if tire.valid?
                  tire.save
                else
                  puts "invalid tire #{tire.manufacturer} #{tire.model} #{tire.tire_code}"
                end
              end
            end
          end
        end
      end

      update_nil_weights_query = "
        update tires
        set weight = (
          select coalesce(avg(t2.weight), 25)
          from tires t2
          where t2.width = tires.width
            and t2.aspect_ratio = tires.aspect_ratio
            and t2.wheel_diameter = tires.wheel_diameter
        )
        where weight is null
      "
      
      update_nil_diameters_query = "
        update tires
        set tire_diameter = (
          select coalesce(avg(t2.tire_diameter), 25)
          from tires t2
          where t2.width = tires.width
            and t2.aspect_ratio = tires.aspect_ratio
            and t2.wheel_diameter = tires.wheel_diameter
        )
        where tire_diameter is null
      "
      
      update_nil_min_wheel_width_query = "
        update tires
        set min_wheel_width = (
          select coalesce(mode(t2.min_wheel_width), 6)
          from tires t2
          where t2.width = tires.width
            and t2.aspect_ratio = tires.aspect_ratio
            and t2.wheel_diameter = tires.wheel_diameter
        )
        where ((min_wheel_width is null) or (min_wheel_width = 0))
      "
      
      update_nil_min_wheel_width_query_step2 = "
        update tires
        set min_wheel_width = (
          select coalesce(mode(t2.min_wheel_width), 6)
          from tires t2
          where t2.width = tires.width
        )
        where ((min_wheel_width is null) or (min_wheel_width = 0))
      "
        
      update_nil_max_wheel_width_query = "
        update tires
        set max_wheel_width = (
          select coalesce(mode(t2.max_wheel_width), 6)
          from tires t2
          where t2.width = tires.width
            and t2.aspect_ratio = tires.aspect_ratio
            and t2.wheel_diameter = tires.wheel_diameter
        )
        where ((max_wheel_width is null) or (max_wheel_width = 0))
      "
      
      update_nil_max_wheel_width_query_step2 = "
        update tires
        set max_wheel_width = (
          select coalesce(mode(t2.max_wheel_width), 6)
          from tires t2
          where t2.width = tires.width
        )
        where ((max_wheel_width is null) or (max_wheel_width = 0))
      "
      
      remove_dupes_query = "
        create temp table temp_tires as
        select distinct manufacturer, model, width, aspect_ratio, wheel_diameter, 
          mode(asymmetrical) as asymmetrical, mode(directional) as directional, mode(treadwear) as treadwear, mode(min_wheel_width) as min_wheel_width,
          mode(max_wheel_width) as max_wheel_width, avg(weight) as weight, avg(tire_diameter) as tire_diameter, 
          mode(tire_type) as tire_type, mode(tire_rack_link) as tire_rack_link, mode(manufacturer_link) as manufacturer_link, 
          mode(model_link) as model_link, mode(notes) as notes
        from tires
        group by manufacturer, model, width, aspect_ratio, wheel_diameter;

        delete from tires;

        insert into tires (manufacturer, model, width, aspect_ratio, wheel_diameter, asymmetrical, directional, treadwear, min_wheel_width, max_wheel_width,
              weight, tire_diameter, tire_type, tire_rack_link, manufacturer_link, model_link, notes)
        select * from temp_tires;

        drop table temp_tires;
      "
      

      ActiveRecord::Base.connection.execute(update_nil_weights_query)
      ActiveRecord::Base.connection.execute(update_nil_diameters_query)
      ActiveRecord::Base.connection.execute(update_nil_min_wheel_width_query)
      ActiveRecord::Base.connection.execute(update_nil_min_wheel_width_query_step2)
      ActiveRecord::Base.connection.execute(update_nil_max_wheel_width_query)
      ActiveRecord::Base.connection.execute(update_nil_max_wheel_width_query_step2)
      ActiveRecord::Base.connection.execute(remove_dupes_query)
    end
  end
  
  def self.add_mode_aggregate
    add_aggregate_query = "
      CREATE OR REPLACE FUNCTION _final_mode(anyarray)
        RETURNS anyelement AS
      $BODY$
          SELECT a
          FROM unnest($1) a
          GROUP BY 1 
          ORDER BY COUNT(1) DESC, 1
          LIMIT 1;
      $BODY$
      LANGUAGE 'sql' IMMUTABLE;

      -- Tell Postgres how to use our aggregate
      CREATE AGGREGATE mode(anyelement) (
        SFUNC=array_append, --Function to call for each row. Just builds the array
        STYPE=anyarray,
        FINALFUNC=_final_mode, --Function to call after everything has been added to array
        INITCOND='{}' --Initialize an empty array when starting
      );
    "
    
    ActiveRecord::Base.connection.execute(add_aggregate_query)
  end
  
  def self.add_unnest_function
    add_unnest_query = "
      CREATE OR REPLACE FUNCTION unnest(anyarray)
        RETURNS SETOF anyelement AS
      $BODY$
      SELECT $1[i] FROM
          generate_series(array_lower($1,1),
                          array_upper($1,1)) i;
      $BODY$
        LANGUAGE 'sql' IMMUTABLE
    "
    ActiveRecord::Base.connection.execute(add_unnest_query)
  end

  @tires = {
    'Toyo' => {
      'Proxes R888' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 100,
        'tire_type' => '0dotr',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => 'http://toyotires.com/tire/pattern/proxes-r888-high-performance-competition-tires',
        'sizes' => {
          '13' => [
            {	'sku' => 	'168280'	,	'width' =>	185	,	'aspect_ratio' =>	60	,	'weight' =>	17.4	,	'tire_diameter' =>	21.6	,	'min_wheel_width' =>	5.0	,	'max_wheel_width' =>	6.5	},
            {	'sku' => 	'168270'	,	'width' =>	205	,	'aspect_ratio' =>	60	,	'weight' =>	19.2	,	'tire_diameter' =>	22.6	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'169360'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	17.9	,	'tire_diameter' =>	20.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	}
          ],
          '14' => [
            {	'sku' => 	'168060'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	19.7	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'168070'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	21	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '15' => [
            {	'sku' => 	'160560'	,	'width' =>	195	,	'aspect_ratio' =>	50	,	'weight' =>	19.4	,	'tire_diameter' =>	22.6	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'155120'	,	'width' =>	195	,	'aspect_ratio' =>	55	,	'weight' =>	20.1	,	'tire_diameter' =>	23.3	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'168200'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	19.8	,	'tire_diameter' =>	23	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'168020'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	20.1	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'160680'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	21.8	,	'tire_diameter' =>	23.7	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'162860'	,	'width' =>	235	,	'aspect_ratio' =>	50	,	'weight' =>	24.4	,	'tire_diameter' =>	24.2	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	}
          ],
          '16' => [
            {	'sku' => 	'168290'	,	'width' =>	195	,	'aspect_ratio' =>	50	,	'weight' =>	19.6	,	'tire_diameter' =>	23.5	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'168220'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	22.5	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'168260'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	20.7	,	'tire_diameter' =>	23.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'168150'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	24	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'168030'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	23.7	,	'tire_diameter' =>	24.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'168050'	,	'width' =>	255	,	'aspect_ratio' =>	50	,	'weight' =>	27	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	9.0	}
          ],
          '17' => [
            {	'sku' => 	'168180'	,	'width' =>	205	,	'aspect_ratio' =>	40	,	'weight' =>	19.4	,	'tire_diameter' =>	23.5	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'168160'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	22.5	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'168170'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	24.5	,	'tire_diameter' =>	25	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'156650'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	23.8	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'168190'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	24.3	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'168130'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	24.9	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'168140'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	26.5	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'168010'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	28.6	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'168540'	,	'width' =>	315	,	'aspect_ratio' =>	35	,	'weight' =>	30.3	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	12.5	}
          ],
          '18' => [
            {	'sku' => 	'168210'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	23.2	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'168230'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	24.9	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'159490'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	26	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'160980'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	25.8	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'168240'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	27.3	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'162800'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	27.9	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'168110'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	29.4	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'168250'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	28	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'160960'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	29.1	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'162810'	,	'width' =>	305	,	'aspect_ratio' =>	35	,	'weight' =>	33	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'162820'	,	'width' =>	315	,	'aspect_ratio' =>	30	,	'weight' =>	30.4	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'162830'	,	'width' =>	335	,	'aspect_ratio' =>	30	,	'weight' =>	32.5	,	'tire_diameter' =>	26	,	'min_wheel_width' =>	11.5	,	'max_wheel_width' =>	12.5	}
          ],
          '19' => [
            {	'sku' => 	'162850'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	25	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'168300'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	26.4	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'162840'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	29.2	,	'tire_diameter' =>	26	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'168000'	,	'width' =>	305	,	'aspect_ratio' =>	30	,	'weight' =>	31	,	'tire_diameter' =>	26.5	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	}
          ],
          '20' => [
            {	'sku' => 	'162980'	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	32	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'162990'	,	'width' =>	315	,	'aspect_ratio' =>	30	,	'weight' =>	32.9	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	}
          ]
        }
      },
      'Proxes R1R' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 140,
        'tire_type' => '1hps',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => 'http://toyotires.com/tire/pattern/proxes-r1r-extreme-performance-summer-tires',
        'sizes' => {
          '15' => [
            {	'sku' => 	'170100'	,	'width' =>	195	,	'aspect_ratio' =>	50	,	'weight' =>	19.6	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'170270'	,	'width' =>	195	,	'aspect_ratio' =>	55	,	'weight' =>	20.3	,	'tire_diameter' =>	23.5	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'170030'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	20.4	,	'tire_diameter' =>	23	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'170140'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	22.1	,	'tire_diameter' =>	23	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	}
          ],
          '16' => [
            {	'sku' => 	'170040'	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	18.9	,	'tire_diameter' =>	23.2	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'170260'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	21.8	,	'tire_diameter' =>	24.3	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'170200'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	22	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'170290'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	22.5	,	'tire_diameter' =>	23.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'170250'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	22.9	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '17' => [
            {	'sku' => 	'170190'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	21.8	,	'tire_diameter' =>	24.5	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'170130'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	23.8	,	'tire_diameter' =>	25	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'170090'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	23.8	,	'tire_diameter' =>	24.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'170170'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	23.6	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'170010'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	23.6	,	'tire_diameter' =>	23.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'170160'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	23.5	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'170180'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	28	,	'tire_diameter' =>	26	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'170150'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	26.4	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'170020'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	26.5	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ],
          '18' => [
            {	'sku' => 	'170050'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	23	,	'tire_diameter' =>	25	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'170110'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	25	,	'tire_diameter' =>	26	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'170060'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	23.6	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'170070'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	26.3	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
          ]
        }
      },
      'Proxes T1R' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => 'http://toyotires.com/tire/pattern/proxes-t1r-ultra-high-performance-summer-tires',
        'sizes' => {
          '14' => [
            {	'sku' => 	'245800'	,	'width' =>	195	,	'aspect_ratio' =>	45	,	'weight' =>	15.2	,	'tire_diameter' =>	20.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245620'	,	'width' =>	195	,	'aspect_ratio' =>	55	,	'weight' =>	16.1	,	'tire_diameter' =>	22.4	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	}
          ],
          '15' => [
            {	'sku' => 	'245630'	,	'width' =>	185	,	'aspect_ratio' =>	55	,	'weight' =>	15.9	,	'tire_diameter' =>	23.0	,	'min_wheel_width' =>	5.0	,	'max_wheel_width' =>	6.5	},
            {	'sku' => 	'245810'	,	'width' =>	195	,	'aspect_ratio' =>	45	,	'weight' =>	15.7	,	'tire_diameter' =>	22.0	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245700'	,	'width' =>	195	,	'aspect_ratio' =>	50	,	'weight' =>	17.0	,	'tire_diameter' =>	22.7	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'245640'	,	'width' =>	195	,	'aspect_ratio' =>	55	,	'weight' =>	17.8	,	'tire_diameter' =>	23.3	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'245820'	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	16.8	,	'tire_diameter' =>	22.2	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245710'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	18.2	,	'tire_diameter' =>	23.1	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245660'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	19.2	,	'tire_diameter' =>	23.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	}
          ],
          '16' => [
            {	'sku' => 	'245730'	,	'width' =>	185	,	'aspect_ratio' =>	50	,	'weight' =>	17.1	,	'tire_diameter' =>	23.2	,	'min_wheel_width' =>	5.0	,	'max_wheel_width' =>	6.5	},
            {	'sku' => 	'245740'	,	'width' =>	195	,	'aspect_ratio' =>	50	,	'weight' =>	18.1	,	'tire_diameter' =>	23.6	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'246700'	,	'width' =>	195	,	'aspect_ratio' =>	55	,	'weight' =>	18.3	,	'tire_diameter' =>	24.3	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'245850'	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	19.0	,	'tire_diameter' =>	23.2	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245750'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	19.0	,	'tire_diameter' =>	24.0	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245670'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	21.9	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245940'	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	18.5	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'245680'	,	'width' =>	215	,	'aspect_ratio' =>	55	,	'weight' =>	23.2	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245860'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	20.2	,	'tire_diameter' =>	23.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'245760'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	21.5	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'245690'	,	'width' =>	225	,	'aspect_ratio' =>	55	,	'weight' =>	24.7	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'246240'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	19.4	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'245870'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	22.0	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	}
          ],
          '17' => [
            {	'sku' => 	'245610'	,	'width' =>	205	,	'aspect_ratio' =>	40	,	'weight' =>	19.4	,	'tire_diameter' =>	23.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'246450'	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	20.3	,	'tire_diameter' =>	24.3	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245770'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	21.4	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245960'	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	20.5	,	'tire_diameter' =>	23.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'245880'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	21.2	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'245780'	,	'width' =>	215	,	'aspect_ratio' =>	50	,	'weight' =>	22.3	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'245600'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	23.2	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'246500'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	25.1	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'246130'	,	'width' =>	225	,	'aspect_ratio' =>	55	,	'weight' =>	26.2	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'245970'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	23.5	,	'tire_diameter' =>	24.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'245890'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	24.7	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'246510'	,	'width' =>	235	,	'aspect_ratio' =>	50	,	'weight' =>	27.1	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'246040'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	20.9	,	'tire_diameter' =>	23.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'245980'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	23.4	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'245900'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	25.8	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'245990'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	24.3	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246160'	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	27.1	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246000'	,	'width' =>	265	,	'aspect_ratio' =>	40	,	'weight' =>	25.6	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	}
          ],
          '18' => [
            {	'sku' => 	'246250'	,	'width' =>	205	,	'aspect_ratio' =>	35	,	'weight' =>	17.9	,	'tire_diameter' =>	23.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'246050'	,	'width' =>	215	,	'aspect_ratio' =>	35	,	'weight' =>	19.4	,	'tire_diameter' =>	23.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'246530'	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	21.6	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'246520'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	22.3	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'246060'	,	'width' =>	225	,	'aspect_ratio' =>	35	,	'weight' =>	20.1	,	'tire_diameter' =>	24.3	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'246010'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	23.2	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'246440'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	23.2	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'246360'	,	'width' =>	235	,	'aspect_ratio' =>	30	,	'weight' =>	20.1	,	'tire_diameter' =>	23.6	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'246020'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	23.8	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246660'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	26.7	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'245790'	,	'width' =>	235	,	'aspect_ratio' =>	50	,	'weight' =>	26.9	,	'tire_diameter' =>	27.1	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'246070'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	23.4	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246030'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	25.6	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'245910'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	27.3	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'246080'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	24.9	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246180'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	26.5	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'245920'	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	28.6	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246090'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	26.0	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'246100'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	26.7	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'246190'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	30.2	,	'tire_diameter' =>	26.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'246560'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	26.9	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'246260'	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	29.1	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'246200'	,	'width' =>	285	,	'aspect_ratio' =>	40	,	'weight' =>	32.2	,	'tire_diameter' =>	26.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'246270'	,	'width' =>	295	,	'aspect_ratio' =>	35	,	'weight' =>	30.9	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.5	}
          ],
          '19' => [
            {	'sku' => 	'246280'	,	'width' =>	225	,	'aspect_ratio' =>	35	,	'weight' =>	21.8	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'246210'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	24.7	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'246110'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	22.1	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246290'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	24.0	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246220'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	26.2	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246710'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	29.5	,	'tire_diameter' =>	27.8	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'246460'	,	'width' =>	255	,	'aspect_ratio' =>	30	,	'weight' =>	24.0	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246300'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	25.4	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246650'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	28.9	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246400'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	24.5	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246690'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	28.2	,	'tire_diameter' =>	26.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246410'	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	25.8	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246310'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	28.0	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'246150'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	30.2	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'246420'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	27.1	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'246320'	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	30.9	,	'tire_diameter' =>	26.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'246570'	,	'width' =>	315	,	'aspect_ratio' =>	25	,	'weight' =>	29.8	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	}
          ],
          '20' => [
            {	'sku' => 	'246470'	,	'width' =>	235	,	'aspect_ratio' =>	30	,	'weight' =>	21.6	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'246540'	,	'width' =>	245	,	'aspect_ratio' =>	30	,	'weight' =>	24.0	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'246330'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	24.9	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246630'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	27.6	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246350'	,	'width' =>	255	,	'aspect_ratio' =>	30	,	'weight' =>	24.7	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246340'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	26.9	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246370'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	26.9	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246430'	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	26.0	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246640'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	28.7	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'246580'	,	'width' =>	285	,	'aspect_ratio' =>	25	,	'weight' =>	26.9	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'246550'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	28.8	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'246380'	,	'width' =>	305	,	'aspect_ratio' =>	25	,	'weight' =>	29.3	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'246600'	,	'width' =>	305	,	'aspect_ratio' =>	30	,	'weight' =>	33.5	,	'tire_diameter' =>	27.2	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'246590'	,	'width' =>	315	,	'aspect_ratio' =>	25	,	'weight' =>	32.6	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'246390'	,	'width' =>	345	,	'aspect_ratio' =>	25	,	'weight' =>	35.5	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	12.0	,	'max_wheel_width' =>	13.0	}
          ],
          '21' => [
            {	'sku' => 	'246480'	,	'width' =>	255	,	'aspect_ratio' =>	30	,	'weight' =>	26.2	,	'tire_diameter' =>	27.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246680'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	30.4	,	'tire_diameter' =>	27.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'246490'	,	'width' =>	295	,	'aspect_ratio' =>	25	,	'weight' =>	29.8	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ],
          '22' => [
            {	'sku' => 	'246610'	,	'width' =>	255	,	'aspect_ratio' =>	30	,	'weight' =>	30.0	,	'tire_diameter' =>	28.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'246670'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	29.5	,	'tire_diameter' =>	28.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'246720'	,	'width' =>	285	,	'aspect_ratio' =>	25	,	'weight' =>	30.9	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'246620'	,	'width' =>	295	,	'aspect_ratio' =>	25	,	'weight' =>	32.4	,	'tire_diameter' =>	27.9	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'Observe G-02 Plus' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '6w',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/toyo/observe_g_02_plus.csv'
      },
      'Observe G2S' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '6w',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/toyo/observe_g2s.csv'
      },
      'Observe Garit KX' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '5hpw',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/toyo/observe_garit_kx.csv'
      },
      'Snowprox S952' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => nil,
        'tire_type' => '5hpw',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/toyo/snowprox_s952.csv'
      },
      'Proxes RA1' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 100,
        'tire_type' => '0dotr',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/toyo/proxes_ra_1.csv'
      },
      'Proxes 1' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 240,
        'tire_type' => '2s',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/toyo/proxes_1.csv'
      },
      'Proxes T1 Sport' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 240,
        'tire_type' => '2s',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/toyo/proxes_t1_sport.csv'
      },
      'Proxes 4' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 300,
        'tire_type' => '3hpa',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://toyotires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/toyo/proxes_4.csv'
      }
    },
    'Dunlop' => {
      'Direzza Sport Z1 Star Spec' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 200,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DDirezza%2BSport%2BZ1%2BStar%2BSpec&cjsku=Dunlop+Direzza+Sport+Z1+Star+Spec+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => 'http://www.dunloptires.com/catalog/direzzaSportZ1StarSpec.html',
        'sizes' => {
          '14' => [
            {'sku' => nil, 'width' => 185, 'aspect_ratio' => 60, 'weight' => nil, 'tire_diameter' => 22.7, 'min_wheel_width' => 5.0, 'max_wheel_width' => 6.5 },
            {'sku' => nil, 'width' => 195, 'aspect_ratio' => 60, 'weight' => nil, 'tire_diameter' => 23.3, 'min_wheel_width' => 5.5, 'max_wheel_width' => 7.0 }
          ],
          '15' => [
            {'sku' => nil, 'width' => 195, 'aspect_ratio' => 50, 'weight' => nil, 'tire_diameter' => 22.7, 'min_wheel_width' => 5.5, 'max_wheel_width' => 7.0 },
            {'sku' => nil, 'width' => 205, 'aspect_ratio' => 50, 'weight' => nil, 'tire_diameter' => 23.1, 'min_wheel_width' => 5.5, 'max_wheel_width' => 7.5 },
            {'sku' => nil, 'width' => 195, 'aspect_ratio' => 55, 'weight' => nil, 'tire_diameter' => 23.5, 'min_wheel_width' => 5.5, 'max_wheel_width' => 7.0 }
          ],
          '16' => [
            {'sku' => nil, 'width' => 205, 'aspect_ratio' => 50, 'weight' => nil, 'tire_diameter' => 24.1, 'min_wheel_width' => 5.5, 'max_wheel_width' => 7.5 },
            {'sku' => nil, 'width' => 225, 'aspect_ratio' => 50, 'weight' => nil, 'tire_diameter' => 24.9, 'min_wheel_width' => 6.0, 'max_wheel_width' => 8.0 },
            {'sku' => nil, 'width' => 205, 'aspect_ratio' => 55, 'weight' => nil, 'tire_diameter' => 24.9, 'min_wheel_width' => 5.5, 'max_wheel_width' => 7.5 }
          ],
          '17' => [
            {'sku' => nil, 'width' => 215, 'aspect_ratio' => 40, 'weight' => nil, 'tire_diameter' => 23.8, 'min_wheel_width' => 7.0, 'max_wheel_width' => 8.5 },
            {'sku' => nil, 'width' => 235, 'aspect_ratio' => 40, 'weight' => nil, 'tire_diameter' => 24.4, 'min_wheel_width' => 8.0, 'max_wheel_width' => 9.5 },
            {'sku' => nil, 'width' => 245, 'aspect_ratio' => 40, 'weight' => nil, 'tire_diameter' => 24.7, 'min_wheel_width' => 8.0, 'max_wheel_width' => 9.5 },
            {'sku' => nil, 'width' => 255, 'aspect_ratio' => 40, 'weight' => nil, 'tire_diameter' => 25.0, 'min_wheel_width' => 8.5, 'max_wheel_width' => 10.0 },
            {'sku' => nil, 'width' => 265, 'aspect_ratio' => 40, 'weight' => nil, 'tire_diameter' => 25.4, 'min_wheel_width' => 9.0, 'max_wheel_width' => 10.5 },
            {'sku' => nil, 'width' => 215, 'aspect_ratio' => 45, 'weight' => nil, 'tire_diameter' => 24.6, 'min_wheel_width' => 7.0, 'max_wheel_width' => 8.0 },
            {'sku' => nil, 'width' => 225, 'aspect_ratio' => 45, 'weight' => nil, 'tire_diameter' => 25.0, 'min_wheel_width' => 7.0, 'max_wheel_width' => 8.5 },
            {'sku' => nil, 'width' => 235, 'aspect_ratio' => 45, 'weight' => nil, 'tire_diameter' => 25.4, 'min_wheel_width' => 7.5, 'max_wheel_width' => 9.0 },
            {'sku' => nil, 'width' => 245, 'aspect_ratio' => 45, 'weight' => nil, 'tire_diameter' => 25.7, 'min_wheel_width' => 7.5, 'max_wheel_width' => 9.0 }
          ],
          '18' => [
            {'sku' => nil, 'width' => 255, 'aspect_ratio' => 35, 'weight' => nil, 'tire_diameter' => 25.0, 'min_wheel_width' => 8.5, 'max_wheel_width' => 10.0 },
            {'sku' => nil, 'width' => 267, 'aspect_ratio' => 35, 'weight' => nil, 'tire_diameter' => 25.3, 'min_wheel_width' => 9.0, 'max_wheel_width' => 10.5 },
            {'sku' => nil, 'width' => 275, 'aspect_ratio' => 35, 'weight' => nil, 'tire_diameter' => 25.6, 'min_wheel_width' => 9.0, 'max_wheel_width' => 11.0 },
            {'sku' => nil, 'width' => 225, 'aspect_ratio' => 40, 'weight' => nil, 'tire_diameter' => 25.1, 'min_wheel_width' => 7.5, 'max_wheel_width' => 9.0 },
            {'sku' => nil, 'width' => 235, 'aspect_ratio' => 40, 'weight' => nil, 'tire_diameter' => 25.4, 'min_wheel_width' => 8.0, 'max_wheel_width' => 9.5 },
            {'sku' => nil, 'width' => 245, 'aspect_ratio' => 40, 'weight' => nil, 'tire_diameter' => 25.7, 'min_wheel_width' => 8.0, 'max_wheel_width' => 9.5 },
            {'sku' => nil, 'width' => 225, 'aspect_ratio' => 45, 'weight' => nil, 'tire_diameter' => 26.0, 'min_wheel_width' => 7.0, 'max_wheel_width' => 8.5 },
            {'sku' => nil, 'width' => 245, 'aspect_ratio' => 45, 'weight' => nil, 'tire_diameter' => 26.6, 'min_wheel_width' => 7.5, 'max_wheel_width' => 9.0 }
          ]
        }
      },
      'SP Sport Maxx TT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 240,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2BMaxx%2BTT&cjsku=Dunlop+SP+Sport+Maxx+TT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => 'http://www.dunloptires.com/dunlop/display_tire.jsp?prodline=SP+SPORT+MAXX+TT&mrktarea=Performance',
        'sizes' => {
          '17' => [
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	55	,	'weight' =>	nil	,	'tire_diameter' =>	27.2	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	55	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '18' => [
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	27.3	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	}
          ],
          '19' => [
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}
          ],
          '20' => [
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}
          ],
          '22' => [
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	29.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	}
          ]
        }
      },
      'SP Sport Maxx GT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 240,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2BMaxx%2BGT&cjsku=Dunlop+SP+Sport+Maxx+GT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => 'http://www.dunloptires.com/dunlop/display_tire.jsp?prodline=SP+SPORT+MAXX+TT&mrktarea=Performance',
        'sizes' => {
          '17' => [
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	}
          ],
          '18' => [
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}
          ],
          '19' => [
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.2	},
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	}
          ],
          '20' => [
            {	'sku' => 	nil	,	'width' =>	305	,	'aspect_ratio' =>	25	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	325	,	'aspect_ratio' =>	25	,	'weight' =>	nil	,	'tire_diameter' =>	26.4	,	'min_wheel_width' =>	11.5	,	'max_wheel_width' =>	12.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	29.1	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	29.4	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	325	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	}
          ],
          '21' => [
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	30.4	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}
          ],
          '22' => [
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	28.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	}
          ]
        }
      },
      'SP Sport Maxx GT DSST' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 240,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2BMaxx%2BGT%2BDSST&cjsku=Dunlop+SP+Sport+Maxx+GT+DSST+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_maxx_gt_dsst.csv'
      },
      'SP Sport 600 DSST CTT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 200,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2B600%2BDSST%2BCTT&cjsku=Dunlop+SP+Sport+600+DSST+CTT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => nil,
        'sizes' => {
          '20' => [
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	34	,	'tire_diameter' =>	28.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	35	,	'tire_diameter' =>	27.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'SP Sport Maxx GT 600 DSST CTT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 200,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2BMaxx%2BGT%2B600%2BDSST%2BCTT&cjsku=Dunlop+SP+Sport+Maxx+GT+600+DSST+CTT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => {
          '20' => [
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	34	,	'tire_diameter' =>	28.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	35	,	'tire_diameter' =>	27.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'SP Sport Maxx' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 240,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2BMaxx&cjsku=Dunlop+SP+Sport+Maxx+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_maxx.csv'
      },
      'Direzza DZ101' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 300,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DDirezza%2BDZ101&cjsku=Dunlop+Direzza+DZ101+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/direzza_dz101.csv'
      },
      'SP Sport 01' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2B01&cjsku=Dunlop+SP+Sport+01+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_01.csv'
      },
      'SP Sport 01 DSST' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2B01%2BDSST&cjsku=Dunlop+SP+Sport+01+DSST+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_01_dsst.csv'
      },
      'SP Sport 01 DSST RunOnFlat' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2B01%2BDSST%2BRunOnFlat&cjsku=Dunlop+SP+Sport+01+DSST+RunOnFlat+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_01_dsst_run_on_flat.csv'
      },
      'SP Sport 2050' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 240,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2B2050&cjsku=Dunlop+SP+Sport+2050+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_2050.csv'
      },
      'Graspic DS-3' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => nil,
        'tire_type' => '6w',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DGraspic%2BDS-3&cjsku=Dunlop+Graspic+DS-3+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/graspic_ds_3.csv'
      },
      'SP Winter Sport M3' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '5hpw',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BWinter%2BSport%2BM3&cjsku=Dunlop+SP+Winter+Sport+M3+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_winter_sport_m3.csv'
      },
      'SP Winter Sport 3D' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '5hpw',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BWinter%2BSport%2B3D&cjsku=Dunlop+SP+Winter+Sport+3D+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.dunloptires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_winter_sport_3d.csv'
      },
      'SP Sport 5000 M' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => 340,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2B5000%2BM&cjsku=Dunlop+SP+Sport+5000+M+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_5000_m.csv'
      },
      'SP Sport 5000 Symmetrical' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => 340,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2B5000%2BSymmetrical&cjsku=Dunlop+SP+Sport+5000+Symmetrical+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_5000_symmetrical.csv'
      },
      'SP Sport 7010 A/S DSST' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 240,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2B7010%2BA%252FS%2BDSST&cjsku=Dunlop+SP+Sport+7010+A%2FS+DSST+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_7010_as_dsst.csv'
      },
      'SP Sport Signature (W&Y)' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 420,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2BSignature%2B%28W%2526Y%29&cjsku=Dunlop+SP+Sport+Signature+%28W%26Y%29+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_signature.csv'
      },
      'SP Sport 7000 A/S' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 340,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2B7000%2BA%252FS&cjsku=Dunlop+SP+Sport+7000+A%2FS+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_7000_as.csv'
      },
      'SP Sport Signature (H&V)' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 460,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DDunlop%26tireModel%3DSP%2BSport%2BSignature%2B%28H%2526V%29&cjsku=Dunlop+SP+Sport+Signature+%28H%26V%29+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/dunlop/sp_sport_signature_hv.csv'
      }
    },
    'Bridgestone' => {
      'Potenza RE-11' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 180,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE-11&cjsku=Bridgestone+Potenza+RE-11+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => 'http://www.bridgestonetire.com/productdetails/QuickSearch/Potenza_RE-11',
        'sizes' => {
          '15' => [
            {'sku' => '102298', 'width' => 195, 'aspect_ratio' => 50, 'weight' => 24, 'tire_diameter' => 22.7, 'min_wheel_width' => 5.5, 'max_wheel_width' => 7.0 },
            {'sku' => '120709', 'width' => 205, 'aspect_ratio' => 50, 'weight' => 24, 'tire_diameter' => 23.1, 'min_wheel_width' => 5.5, 'max_wheel_width' => 7.5 }
          ],
          '16' => [
            {'sku' => '102315', 'width' => 205, 'aspect_ratio' => 45, 'weight' => 25, 'tire_diameter' => 23.2, 'min_wheel_width' => 6.5, 'max_wheel_width' => 7.5 },
            {'sku' => '079705', 'width' => 205, 'aspect_ratio' => 55, 'weight' => 25, 'tire_diameter' => 24.9, 'min_wheel_width' => 5.5, 'max_wheel_width' => 7.5 },
            {'sku' => '079858', 'width' => 225, 'aspect_ratio' => 50, 'weight' => 24, 'tire_diameter' => 24.9, 'min_wheel_width' => 6.0, 'max_wheel_width' => 8.0 }
          ],
          '17' => [
            {	'sku' => 	'079875'	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	24	,	'tire_diameter' =>	24.3	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'109540'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	23	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'079892'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	28	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'079909'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	28	,	'tire_diameter' =>	25    ,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'079807'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	28	,	'tire_diameter' =>	24.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'079722'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	28	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'079773'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	28	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'079824'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	28	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'086182'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	28	,	'tire_diameter' =>	25    ,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}

          ],
          '18' => [
            {	'sku' => 	'109523'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	29	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'079926'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	25	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'079841'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	29	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'079977'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	28	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'079943'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	28	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'079739'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	28	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'086199'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	29	,	'tire_diameter' =>	25    ,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'079756'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	29	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'109591'	,	'width' =>	265	,	'aspect_ratio' =>	40	,	'weight' =>	29	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'109574'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	32	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}

          ],
          '19' => [
            {	'sku' => 	'086216'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	30	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'086233'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	28	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'141840'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	29	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'109506'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	29	,	'tire_diameter' =>	26    ,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'086250'	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	29	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'109659'	,	'width' =>	305	,	'aspect_ratio' =>	30	,	'weight' =>	31	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	}

          ]
        }
      },
      'Potenza RE-070' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 140,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE070&cjsku=Bridgestone+Potenza+RE070+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => 'http://www.bridgestonetire.com/productdetails/QuickSearch/Potenza_RE070',
        'sizes' => {
          '17' => [
            {	'sku' => 	'118363'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	24.0	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'013626'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	26.0	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'118380'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	28.0	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>  10.0	}
          ]
        }
      },
      'Potenza RE-070R RFT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 140,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE070R%2BRFT&cjsku=Bridgestone+Potenza+RE070R+RFT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => 'http://www.bridgestonetire.com/productdetails/QuickSearch/Potenza_RE070',
        'sizes' => {
          '20' => [
            {	'sku' => 	'001310'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	35.0	,	'tire_diameter' =>	28.0	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'001327'	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	40.0	,	'tire_diameter' =>	27.9	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'Potenza RE-070R2 RFT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 140,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE070R%2BR2%2BRFT&cjsku=Bridgestone+Potenza+RE070R+R2+RFT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => 'http://www.bridgestonetire.com/productdetails/QuickSearch/Potenza_RE070',
        'sizes' => {
          '20' => [
            {	'sku' => 	'001310'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	35.0	,	'tire_diameter' =>	28.0	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'001327'	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	40.0	,	'tire_diameter' =>	27.9	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'Potenza RE050' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 140,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE050&cjsku=Bridgestone+Potenza+RE050+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re050.csv'
      },
      'Potenza RE050 RFT' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 140,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE050%2BRFT&cjsku=Bridgestone+Potenza+RE050+RFT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re050_rft.csv'
      },
      'Potenza RE050A' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 140,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE050A&cjsku=Bridgestone+Potenza+RE050A+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re050a.csv'
      },
      'Potenza RE050A I RFT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 140,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE050A%2BI%2BRFT&cjsku=Bridgestone+Potenza+RE050A+I+RFT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re050a_I_rft.csv'
      },
      'Potenza RE050A Pole Position' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE050A%2BPole%2BPosition&cjsku=Bridgestone+Potenza+RE050A+Pole+Position+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re050a_pole_position.csv'
      },
      'Potenza RE050A Pole Position RFT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE050A%2BPole%2BPosition%2BRFT&cjsku=Bridgestone+Potenza+RE050A+Pole+Position+RFT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re050a_pole_position_rft.csv'
      },
      'Potenza RE050A RFT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 140,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE050A%2BRFT&cjsku=Bridgestone+Potenza+RE050A+RFT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re050a_rft.csv'
      },
      'Potenza S001' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BS001&cjsku=Bridgestone+Potenza+S001+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_s001.csv'
      },
      'Potenza S-02' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 140,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BS-02&cjsku=Bridgestone+Potenza+S-02+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_s02.csv'
      },
      'Potenza S-02 A' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 140,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BS-02%2BA&cjsku=Bridgestone+Potenza+S-02+A+Tire" target="_blank">
                          Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_s02a.csv'
      },
      'Potenza S-04 Pole Position' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BS-04%2BPole%2BPosition&cjsku=Bridgestone+Potenza+S-04+Pole+Position+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_s04_pole_position.csv'
      },
      'Blizzak WS-60' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '6w',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DBlizzak%2BWS60&cjsku=Bridgestone+Blizzak+WS60+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/blizzak_ws60.csv'
      },
      'Blizzak WS-70' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '6w',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DBlizzak%2BWS70&cjsku=Bridgestone+Blizzak+WS70+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/blizzak_ws70.csv'
      },
      'Blizzak LM-60' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '5hpw',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DBlizzak%2BLM-60&cjsku=Bridgestone+Blizzak+LM-60+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bridgestonetire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/blizzak_lm60.csv'
      },
      'Potenza RE960AS Pole Position' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE960AS%2BPole%2BPosition&cjsku=Bridgestone+Potenza+RE960AS+Pole+Position+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re960_as_pole_position.csv'
      },
      'Potenza RE970AS Pole Position' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE970AS%2BPole%2BPosition&cjsku=Bridgestone+Potenza+RE970AS+Pole+Position+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re970as_pole_position.csv'
      },
      'Potenza G 019 Grid' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 440,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BG%2B019%2BGrid&cjsku=Bridgestone+Potenza+G+019+Grid+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_g_019_grid.csv'
      },
      'Potenza RE92' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => 260,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE92&cjsku=Bridgestone+Potenza+RE92+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re92.csv'
      },
      'Potenza RE92a' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => 260,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBridgestone%26tireModel%3DPotenza%2BRE92A&cjsku=Bridgestone+Potenza+RE92A+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/bridgestone/potenza_re92a.csv'
      }
    },
    'Hankook' => {
      'Ventus RS-3' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 140,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DHankook%26tireModel%3DVentus%2BR-S3&cjsku=Hankook+Ventus+R-S3+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.hankooktireusa.com/Main/default.aspx',
        'model_link' => 'http://www.hankooktireusa.com/Product/product.aspx?pageNum=1&subNum=1&ChildNum=2&FnCode=02',
        'sizes' => {
          '15' => [
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	23	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	}
          ],
          '16' => [
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	nil	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	}
          ],
          '17' => [
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	}

          ],
          '18' => [
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	26.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	}
          ],
          '19' => [
            {	'sku' => 	nil	,	'width' =>	305	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	}
          ],
          '20' => [
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	28	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}
          ]
        }
      },
      'Ventus Z214' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => 40,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DHankook%26tireModel%3DVentus%2BZ214&cjsku=Hankook+Ventus+Z214+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.hankooktireusa.com/Main/default.aspx',
        'model_link' => 'http://www.hankooktireusa.com/Product/product.aspx?pageNum=1&subNum=1&ChildNum=6&FnCode=062',
        'sizes' => {
          '13' => [
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	20.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	}
          ],
          '14' => [
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '15' => [
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	23.0	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	}
          ],
          '16' => [
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	23.9	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	9.0	}
          ],
          '17' => [
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	}
          ],
          '18' => [
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'Ventus V12 Evo' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DHankook%26tireModel%3DVentus%2BV12%2Bevo%2BK110&cjsku=Hankook+Ventus+V12+evo+K110+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.hankooktireusa.com/Main/default.aspx',
        'model_link' => 'http://www.hankooktireusa.com/Product/product.aspx?pageNum=1&subNum=1&ChildNum=2&FnCode=02',
        'sizes' => {
          '16' => [
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	}
          ],
          '17' => [
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.3	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	}
          ],
          '18' => [
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	}
          ],
          '19' => [
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	305	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	}
          ],
          '20' => [
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	25	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	295	,	'aspect_ratio' =>	25	,	'weight' =>	nil	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	305	,	'aspect_ratio' =>	25	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	28.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	29.1	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	28.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ],
          '21' => [
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	27.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	}
          ]
        }
      },
      'Ventus V4 ES H105' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 420,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DHankook%26tireModel%3DVentus%2BV4%2BES%2BH105&cjsku=Hankook+Ventus+V4+ES+H105+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/hankook/ventus_v4_es_h105.csv'
      },
      'Optimo H426' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => 440,
        'tire_type' => '4a',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DHankook%26tireModel%3DOptimo%2BH426&cjsku=Hankook+Optimo+H426+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/hankook/optimo_h426.csv'
      }
    },
    'Yokohama' => {
      'Advan A048' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 60,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DYokohama%26tireModel%3DADVAN%2BA048&cjsku=Yokohama+ADVAN+A048+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.yokohamatire.com',
        'model_link' => 'http://www.yokohamatire.com/tires/detail/advan_a048',
        'sizes' => {
          '15' => [
            {	'sku' => 	'4807'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	18.8	,	'tire_diameter' =>	23.0	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'4806'	,	'width' =>	205	,	'aspect_ratio' =>	60	,	'weight' =>	20.9	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'4808'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	22.0	,	'tire_diameter' =>	23.7	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '16' => [
            {	'sku' => 	'4810'	,	'width' =>	195	,	'aspect_ratio' =>	50	,	'weight' =>	19.8	,	'tire_diameter' =>	23.7	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'4809'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	22.6	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'4842'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	21.6	,	'tire_diameter' =>	23.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'4811'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	24.1	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '17' => [
            {	'sku' => 	'4814'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	23.2	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'4815'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	25.0	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'4816'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	25.3	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
          ],
          '18' => [
            {	'sku' => 	'4801'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	22.9	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'4818'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	24.5	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'4802'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	26.0	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'4803'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	26.6	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'4819'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	27.0	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'Advan Neova AD08' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 180,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DYokohama%26tireModel%3DADVAN%2BNeova%2BAD08&cjsku=Yokohama+ADVAN+Neova+AD08+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.yokohamatire.com',
        'model_link' => 'http://www.yokohamatire.com/tires/detail/advan_a048',
        'sizes' => {
          '15' => [
            {	'sku' => 	'8000'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	20.2	,	'tire_diameter' =>	23.0	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	}
          ],
          '16' => [
            {	'sku' => 	'8001'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	21.0	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'8002'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	22.9	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '17' => [
            {	'sku' => 	'8003'	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	21.4	,	'tire_diameter' =>	24.2	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'8004'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	22.1	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'8005'	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	21.3	,	'tire_diameter' =>	23.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'8006'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	22.0	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'8007'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	23.6	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'8008'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	24.4	,	'tire_diameter' =>	24.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'8009'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	24.7	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'8010'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	25.5	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'8011'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	26.3	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'8012'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	26.4	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}
          ],
          '18' => [
            {	'sku' => 	'8013'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	23.1	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'8014'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	22.9	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'8015'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	24.7	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'8016'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	25.1	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'8017'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	26.2	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'8018'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	27.5	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'8019'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	25.9	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'8020'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	27.6	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'8021'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	27.4	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'8032'	,	'width' =>	265	,	'aspect_ratio' =>	40	,	'weight' =>	28.8	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'8022'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	27.1	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'8023'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	29.2	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ],
          '19' => [
            {	'sku' => 	'8024'	,	'width' =>	225	,	'aspect_ratio' =>	35	,	'weight' =>	23.1	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'8025'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	24.4	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'8026'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	25.6	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'8033'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	27.6	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'8027'	,	'width' =>	255	,	'aspect_ratio' =>	30	,	'weight' =>	25.4	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'8028'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	27.1	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'8029'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	26.5	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'8034'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	28.5	,	'tire_diameter' =>	26.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'8030'	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	27.6	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'8035'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	29.8	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'8031'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	30.5	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'ADVAN Sport' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 180,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DYokohama%26tireModel%3DADVAN%2BSport&cjsku=Yokohama+ADVAN+Sport+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.yokohamatire.com',
        'model_link' => '',
        'sizes' => 'tire_data/yokohama/advan_sport.csv'
      },
      'ADVAN Sport ZPS' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 180,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DYokohama%26tireModel%3DADVAN%2BSport%2BZPS&cjsku=Yokohama+ADVAN+Sport+ZPS+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.yokohamatire.com',
        'model_link' => '',
        'sizes' => 'tire_data/yokohama/advan_sport_zps.csv'
      },
      'ADVAN S.4.' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DYokohama%26tireModel%3DADVAN%2BS.4.&cjsku=Yokohama+ADVAN+S.4.+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/yokohama/advan_s4.csv'
      },
      'AVID ENVigor' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 560,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DYokohama%26tireModel%3DAVID%2BENVigor%2B%28W%29&cjsku=Yokohama+AVID+ENVigor+%28W%29+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/yokohama/avid_envigor.csv'
      }
    },
    'Nitto' => {
      'NT01' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 100,
        'tire_type' => '0dotr',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.nittotire.com/',
        'model_link' => 'http://nittotire.com/index.html#index.tire.nt01',
        'sizes' => {
          '14' => [
            {	'sku' => 	'371-090'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	}
          ],
          '15' => [
            {	'sku' => 	'371-080'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	23.0	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'371-160'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	23.0	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	}
          ],
          '16' => [
            {	'sku' => 	'371-070'	,	'width' =>	245	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	}
          ],
          '17' => [
            {	'sku' => 	'371-040'	,	'width' =>	205	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	23.5	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'371-170'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'371-060'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'371-100'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'371-050'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'371-150'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'371-030'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'371-140'	,	'width' =>	315	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	12.5	}
          ],
          '18' => [
            {	'sku' => 	'371-110'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'371-120'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'371-020'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'371-010'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'371-130'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'371-000'	,	'width' =>	315	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	}
          ]
        }
      },
      'NT05' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 200,
        'tire_type' => '2s',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.nittotire.com/',
        'model_link' => 'http://nittotire.com/index.html#index.tire.nt05',
        'sizes' => {
          '17' => [
            {	'sku' => 	'207-120'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'207-130'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'207-010'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'207-000'	,	'width' =>	315	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	12.5	}
          ],
          '18' => [
            {	'sku' => 	'207-240'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'207-160'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'207-030'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'207-060'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'207-020'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'207-050'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'207-140'	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'207-150'	,	'width' =>	295	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'207-170'	,	'width' =>	295	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	28.5	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	}
          ],
          '19' => [
            {	'sku' => 	'207-190'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'207-080'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'207-090'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'207-200'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'207-070'	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'207-100'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'207-180'	,	'width' =>	335	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.9	,	'min_wheel_width' =>	11.5	,	'max_wheel_width' =>	12.5	}
          ],
          '20' => [
            {	'sku' => 	'207-210'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'207-230'	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	29.1	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'207-220'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'207-040'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	28.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'207-110'	,	'width' =>	315	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	28.6	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	12.5	}
          ],
        }
      }
#      ,
#      'NeoGen' => {
#      'asymmetrical' => true,
#      'directional' => false,
#      'treadwear' => 240,
#      'tire_type' => '3hpa',
#      'tire_rack_link' => '',
#      'manufacturer_link' => 'http://www.nittotire.com/',
#      'model_link' => '',
#      'sizes' => 'tire_data/nitto/neo_gen.csv'
#      },
#      'NT450' => {
#      'asymmetrical' => false,
#      'directional' => true,
#      'treadwear' => 300,
#      'tire_type' => '3hpa',
#      'tire_rack_link' => '',
#      'manufacturer_link' => 'http://www.nittotire.com/',
#      'model_link' => '',
#      'sizes' => 'tire_data/nitto/nt450.csv'
#      },
#      'Invo' => {
#      'asymmetrical' => true,
#      'directional' => false,
#      'treadwear' => 300,
#      'tire_type' => '2s',
#      'tire_rack_link' => '',
#      'manufacturer_link' => 'http://www.nittotire.com/',
#      'model_link' => '',
#      'sizes' => 'tire_data/nitto/invo.csv'
#      },
#      'NT555' => {
#      'asymmetrical' => false,
#      'directional' => true,
#      'treadwear' => 300,
#      'tire_type' => '2s',
#      'tire_rack_link' => '',
#      'manufacturer_link' => 'http://www.nittotire.com/',
#      'model_link' => '',
#      'sizes' => 'tire_data/nitto/nt555.csv'
#      }
    },
    'Falken' => {
      'Azenis RT-615K' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 200,
        'tire_type' => '1hps',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.falkentire.com/',
        'model_link' => 'http://www.falkentire.com/Tires/Passenger-Car/Azenis-RT-615K-14',
        'sizes' => {
          '14' => [
            {	'sku' => 	'28231452'	,	'width' =>	195	,	'aspect_ratio' =>	60	,	'weight' =>	19.0	,	'tire_diameter' =>	23.2	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	}
          ],
          '15' => [
            {	'sku' => 	'28233572'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	21.0	,	'tire_diameter' =>	23.2	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	}
          ],
          '16' => [
            {	'sku' => 	'28233680'	,	'width' =>	205	,	'aspect_ratio' =>	40	,	'weight' =>	18.0	,	'tire_diameter' =>	22.5	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'28233656'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	22.0	,	'tire_diameter' =>	23.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'28233672'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	25.0	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '17' => [
            {	'sku' => 	'28233740'	,	'width' =>	205	,	'aspect_ratio' =>	40	,	'weight' =>	19.0	,	'tire_diameter' =>	23.4	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'28233741'	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	20.0	,	'tire_diameter' =>	23.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'28233792'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	23.0	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'28233795'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	25.0	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'28233793'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	24.0	,	'tire_diameter' =>	24.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'28233784'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	27.0	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'28233796'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	27.0	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'28233798'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	28.0	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ],
          '18' => [
            {	'sku' => 	'28233892'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	24.0	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'28233893'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	24.0	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'28233894'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	27.0	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'28233844'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	28.0	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'28233806'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	28.0	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'28233807'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	27.0	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'28233850'	,	'width' =>	295	,	'aspect_ratio' =>	40	,	'weight' =>	33.0	,	'tire_diameter' =>	27.2	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'28233848'	,	'width' =>	315	,	'aspect_ratio' =>	30	,	'weight' =>	32.0	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	}
          ]
        }
      },
      'Eurowinter HS439' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => nil,
        'tire_type' => '5hpw',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.falkentire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/falken/eurowinter_hs439.csv'
      },
      'Espia EPZ' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => nil,
        'tire_type' => '6w',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.falkentire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/falken/espia_epz.csv'
      },
      'Azenis PT722 A/S' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 600,
        'tire_type' => '3hpa',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.falkentire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/falken/azenis_pt722_as.csv'
      },
      'ZIEX ZE-912' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 480,
        'tire_type' => '3hpa',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.falkentire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/falken/ziex_ze_912.csv'
      },
      'FK452' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 300,
        'tire_type' => '2s',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.falkentire.com/',
        'model_link' => '',
        'sizes' => 'tire_data/falken/fk452.csv'
      }
    },
    'BF Goodrich' => {
      'g-Force T/A KDW' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 300,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBFGoodrich%26tireModel%3Dg-Force%2BT%252FA%2BKDW%2B2&cjsku=BFGoodrich+g-Force+T%2FA+KDW+2+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bfgoodrichtires.com/',
        'model_link' => 'http://www.bfgoodrichtires.com/tire-selector/category/tuner-tires/g-force-t-a-kdw/tire-details',
        'sizes' => {
          '16' => [
            {	'sku' => 	'90078'	,	'width' =>	205	,	'aspect_ratio' =>	40	,	'weight' =>	19.5	,	'tire_diameter' =>	22.4	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'71146'	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	20.1	,	'tire_diameter' =>	23.1	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'86547'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	21.5	,	'tire_diameter' =>	24.1	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'08847'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	22.5	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'93128'	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	20.1	,	'tire_diameter' =>	23.0	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'84309'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	22.5	,	'tire_diameter' =>	23.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'30005'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	23.8	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'17082'	,	'width' =>	225	,	'aspect_ratio' =>	55	,	'weight' =>	25.0	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '17' => [
            {	'sku' => 	'86358'	,	'width' =>	205	,	'aspect_ratio' =>	40	,	'weight' =>	20.2	,	'tire_diameter' =>	23.5	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'44287'	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	21.5	,	'tire_diameter' =>	24.3	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'79712'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	22.5	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'41083'	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	21.3	,	'tire_diameter' =>	23.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'40190'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	22.2	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'93358'	,	'width' =>	215	,	'aspect_ratio' =>	50	,	'weight' =>	23.2	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'67379'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	23.8	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'77326'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	24.7	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'53580'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	23.1	,	'tire_diameter' =>	24.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'93696'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	24.6	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'28538'	,	'width' =>	235	,	'aspect_ratio' =>	50	,	'weight' =>	25.4	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'11415'	,	'width' =>	235	,	'aspect_ratio' =>	55	,	'weight' =>	27.8	,	'tire_diameter' =>	27.2	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'88828'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	24.1	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'88499'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	25.2	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'94564'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	26.2	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'17970'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	27.5	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ],
          '18' => [
            {	'sku' => 	'79613'	,	'width' =>	215	,	'aspect_ratio' =>	35	,	'weight' =>	21.4	,	'tire_diameter' =>	23.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'88309'	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	22.3	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'70256'	,	'width' =>	225	,	'aspect_ratio' =>	35	,	'weight' =>	22.1	,	'tire_diameter' =>	24.3	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'61972'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	22.9	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'86741'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	24.8	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'86721'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	23.8	,	'tire_diameter' =>	24.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'97900'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	25.1	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'49336'	,	'width' =>	235	,	'aspect_ratio' =>	50	,	'weight' =>	27.8	,	'tire_diameter' =>	27.3	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'63734'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	24.8	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'68815'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	26.3	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'84649'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	27.7	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'70126'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	25.9	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'85761'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	27.0	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'84296'	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	28.5	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'97867'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	26.9	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'46785'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	27.5	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'76132'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	28.8	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'84124'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	28.6	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'76315'	,	'width' =>	285	,	'aspect_ratio' =>	60	,	'weight' =>	37.8	,	'tire_diameter' =>	31.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'88175'	,	'width' =>	295	,	'aspect_ratio' =>	35	,	'weight' =>	30.3	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'58900'	,	'width' =>	335	,	'aspect_ratio' =>	30	,	'weight' =>	35.3	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	11.5	,	'max_wheel_width' =>	12.5	}
          ],
          '19' => [
            {	'sku' => 	'93396'	,	'width' =>	215	,	'aspect_ratio' =>	35	,	'weight' =>	22.4	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'77664'	,	'width' =>	225	,	'aspect_ratio' =>	35	,	'weight' =>	23.6	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'76922'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	25.1	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'98647'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	26.1	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'96340'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	27.5	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'96121'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	26.6	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'95089'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	27.8	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'86557'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	29.0	,	'tire_diameter' =>	26.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'97373'	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	31.1	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'86811'	,	'width' =>	295	,	'aspect_ratio' =>	35	,	'weight' =>	31.9	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.5	}
          ],
          '20' => [
            {	'sku' => 	'84431'	,	'width' =>	225	,	'aspect_ratio' =>	30	,	'weight' =>	22.5	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'44959'	,	'width' =>	225	,	'aspect_ratio' =>	35	,	'weight' =>	21.0	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'92177'	,	'width' =>	245	,	'aspect_ratio' =>	30	,	'weight' =>	25.2	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'96751'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	26.5	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'72146'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	28.3	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'97871'	,	'width' =>	255	,	'aspect_ratio' =>	30	,	'weight' =>	27.1	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'91690'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	28.5	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'44477'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	28.7	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'95451'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	29.0	,	'tire_diameter' =>	27.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'81848'	,	'width' =>	265	,	'aspect_ratio' =>	50	,	'weight' =>	36.3	,	'tire_diameter' =>	30.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'63300'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	31.5	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'93701'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	30.6	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'87929'	,	'width' =>	285	,	'aspect_ratio' =>	55	,	'weight' =>	38.3	,	'tire_diameter' =>	32.3	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'59160'	,	'width' =>	295	,	'aspect_ratio' =>	40	,	'weight' =>	35.7	,	'tire_diameter' =>	29.5	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'83036'	,	'width' =>	295	,	'aspect_ratio' =>	45	,	'weight' =>	38.5	,	'tire_diameter' =>	30.5	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'g-Force R1' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => 40,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBFGoodrich%26tireModel%3Dg-Force%2BR1&cjsku=BFGoodrich+g-Force+R1+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.bfgoodrichtires.com/',
        'model_link' => 'http://www.bfgoodrichtires.com/tire-selector/name/g-force-r1-tires',
        'sizes' => {
          '15' => [
            {	'sku' => 	'31575'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	18.7	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'61446'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	20.2	,	'tire_diameter' =>	23.6	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '16' => [
            {	'sku' => 	'14120'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	20.3	,	'tire_diameter' =>	24.5	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'17463'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	21.7	,	'tire_diameter' =>	24.5	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'44288'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	22.1	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	}
          ],
          '17' => [
            {	'sku' => 	'49121'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	21.7	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'8860'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	21.9	,	'tire_diameter' =>	24.2	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'50260'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	22.7	,	'tire_diameter' =>	24.2	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'13273'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	23.5	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'64568'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	26.0	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'94637'	,	'width' =>	315	,	'aspect_ratio' =>	35	,	'weight' =>	27.4	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	}
          ],
          '18' => [
            {	'sku' => 	'13982'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	21.9	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'3884'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	23.5	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'34527'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	24.9	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'74887'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	25.6	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'47005'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	25.3	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'43792'	,	'width' =>	335	,	'aspect_ratio' =>	30	,	'weight' =>	29.6	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	12.0	,	'max_wheel_width' =>	13.0	}
          ]
        }
      },
      'g-Force Super Sport A/S' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBFGoodrich%26tireModel%3Dg-Force%2BSuper%2BSport%2BA%252FS&cjsku=BFGoodrich+g-Force+Super+Sport+A%2FS+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/bfgoodrich/gforce_super_sport_as.csv'
      },
      'g-Force T/A KDWS' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DBFGoodrich%26tireModel%3Dg-Force%2BT%252FA%2BKDWS&cjsku=BFGoodrich+g-Force+T%2FA+KDWS+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/bfgoodrich/gforce_ta_kdws.csv'
      }
    },
    'Goodyear' => {
      'Eagle F1 Supercar G: 2' => {
        'asymmetrical' => true,
        'directional' => true,
        'treadwear' => 220,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DGoodyear%26tireModel%3DEagle%2BF1%2BSupercar%2BG%3A%2B2&cjsku=Goodyear+Eagle+F1+Supercar+G%3A+2+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.goodyeartires.com/',
        'model_link' => 'http://www.goodyeartires.com/tire/eaglef1-supercar-g2/',
        'sizes' => {
          '19' => [
            {	'sku' => 	nil,	'width' =>	265	,	'aspect_ratio' =>	40	,	'weight' =>	25.0	,	'tire_diameter' =>	27.4	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	}
          ],
          '20' => [
            {	'sku' => 	nil,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	25.0	,	'tire_diameter' =>	27.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'Eagle F1 Supercar G: 2 Runflat' => {
        'asymmetrical' => true,
        'directional' => true,
        'treadwear' => 220,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DGoodyear%26tireModel%3DEagle%2BF1%2BSupercar%2BG%3A%2B2%2BRunOnFlat&cjsku=Goodyear+Eagle+F1+Supercar+G%3A+2+RunOnFlat+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.goodyeartires.com/',
        'model_link' => 'http://www.goodyeartires.com/tire/eaglef1-supercar-g2-rof/',
        'sizes' => {
          '18' => [
            {	'sku' => 	nil,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	25.0	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ],
          '19' => [
            {	'sku' => 	nil,	'width' =>	325	,	'aspect_ratio' =>	30	,	'weight' =>	25.0	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	12.0	,	'max_wheel_width' =>	13.0	}
          ]
        }
      },
      'Eagle F1 Asymmetric' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 240,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DGoodyear%26tireModel%3DEagle%2BF1%2BAsymmetric&cjsku=Goodyear+Eagle+F1+Asymmetric+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.goodyeartires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/goodyear/eagle_f1_asymmetric.csv'
      },
      'Eagle F1 GS-D3' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DGoodyear%26tireModel%3DEagle%2BF1%2BGS-D3&cjsku=Goodyear+Eagle+F1+GS-D3+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.goodyeartires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/goodyear/eagle_f1_gs_d3.csv'
      },
      'Eagle F1 Supercar' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 220,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DGoodyear%26tireModel%3DEagle%2BF1%2BSupercar&cjsku=Goodyear+Eagle+F1+Supercar+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.goodyeartires.com/',
        'model_link' => '',
        'sizes' => 'tire_data/goodyear/eagle_f1_supercar.csv'
      },
      'Eagle F1 All Season' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 420,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DGoodyear%26tireModel%3DEagle%2BF1%2BAll%2BSeason&cjsku=Goodyear+Eagle+F1+All+Season+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/goodyear/eagle_f1_all_season.csv'
      },
      'Eagle GT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DGoodyear%26tireModel%3DEagle%2BGT%2B%28W%29&cjsku=Goodyear+Eagle+GT+%28W%29+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/goodyear/eagle_gt.csv'
      }
    },
    'Michelin' => {
      'Pilot Sport Cup' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 80,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BSport%2BCup&cjsku=Michelin+Pilot+Sport+Cup+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => 'http://www.michelinman.com/tire-selector/category/ultra-high-performance-sport/pilot-sport-cup/tire-details',
        'sizes' => {
          '18' => [
            {	'sku' => 	'87503'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	20.48	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'53827'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	21.43	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'60480'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	23.48	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'81118'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	24.54	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'80852'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	24.82	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ],
          '19' => [
            {	'sku' => 	'88851'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	21.01	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'21439'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	20.19	,	'tire_diameter' =>	25.79	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'65562'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	22.95	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'15839'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	24.25	,	'tire_diameter' =>	26.34	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'32048'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	27.65	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'54909'	,	'width' =>	305	,	'aspect_ratio' =>	30	,	'weight' =>	26.46	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'73334'	,	'width' =>	325	,	'aspect_ratio' =>	30	,	'weight' =>	28.13	,	'tire_diameter' =>	26.73	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'6610'	,	'width' =>	345	,	'aspect_ratio' =>	30	,	'weight' =>	31.68	,	'tire_diameter' =>	27.2	,	'min_wheel_width' =>	11.5	,	'max_wheel_width' =>	12.5	}
          ],
          '20' => [
            {	'sku' => 	'2423'	,	'width' =>	245	,	'aspect_ratio' =>	30	,	'weight' =>	23.35	,	'tire_diameter' =>	25.83	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'26244'	,	'width' =>	315	,	'aspect_ratio' =>	25	,	'weight' =>	26.46	,	'tire_diameter' =>	26.38	,	'min_wheel_width' =>	11.5	,	'max_wheel_width' =>	12.5	},
            {	'sku' => 	'10321'	,	'width' =>	335	,	'aspect_ratio' =>	25	,	'weight' =>	31.81	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	11.5	,	'max_wheel_width' =>	12.5	}
          ]
        }
      },
      'Pilot Sport Cup ZP' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 80,
        'tire_type' => '0dotr',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_sport_cup_zp.csv'
      },
      'Pilot Sport Cup+ / N-Spec' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 80,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BSport%2BCup%252B%2B%252F%2BN-Spec&cjsku=Michelin+Pilot+Sport+Cup%2B+%2F+N-Spec+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_sport_cup_plus.csv'
      },
      'Pilot Super Sport' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 300,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BSuper%2BSport&cjsku=Michelin+Pilot+Super+Sport+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => 'http://www.michelinman.com/tire-selector/category/ultra-high-performance-sport/pilot-super-sport/tire-details',
        'sizes' => {
          '17' => [
            {	'sku' => 	'72102'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	21.69	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'89738'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	22.77	,	'tire_diameter' =>	25	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'63248'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	23.94	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'45737'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	23.1	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	}
          ],
          '18' => [
            {	'sku' => 	'43199'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	22.82	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'15317'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	21.89	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'37359'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	25.24	,	'tire_diameter' =>	26.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'1966'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	23.57	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'3264'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	23.72	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'91157'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	24.49	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'7807'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	24.74	,	'tire_diameter' =>	25	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'14912'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	25.31	,	'tire_diameter' =>	26	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'34639'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	26.06	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'5512'	,	'width' =>	265	,	'aspect_ratio' =>	40	,	'weight' =>	27.25	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'99872'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	28.33	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'20497'	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	28.81	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	}
          ],
          '19' => [
            {	'sku' => 	'63973'	,	'width' =>	225	,	'aspect_ratio' =>	35	,	'weight' =>	21.16	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'18640'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	21.8	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'62936'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	23.15	,	'tire_diameter' =>	27	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'16289'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	22.42	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'15466'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	23.17	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'36814'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	26.1	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'31567'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	24.36	,	'tire_diameter' =>	26	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'16609'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	24.85	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'99229'	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	25.82	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'22002'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	27.49	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'78686'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	28.17	,	'tire_diameter' =>	26	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'60721'	,	'width' =>	305	,	'aspect_ratio' =>	30	,	'weight' =>	29.87	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	}
          ],
          '20' => [
            {	'sku' => 	'7688'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	22.38	,	'tire_diameter' =>	26.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'20206'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'79020'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	25.53	,	'tire_diameter' =>	27	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'12845'	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	30.69	,	'tire_diameter' =>	29.1	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'9106'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	27.18	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'23958'	,	'width' =>	285	,	'aspect_ratio' =>	25	,	'weight' =>	25.46	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'71509'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	24.54	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'42877'	,	'width' =>	295	,	'aspect_ratio' =>	25	,	'weight' =>	27.36	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'28274'	,	'width' =>	295	,	'aspect_ratio' =>	35	,	'weight' =>	30.84	,	'tire_diameter' =>	28.1	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'19605'	,	'width' =>	315	,	'aspect_ratio' =>	35	,	'weight' =>	33.27	,	'tire_diameter' =>	28.7	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	12.5	},
            {	'sku' => 	'65438'	,	'width' =>	345	,	'aspect_ratio' =>	30	,	'weight' =>	34.88	,	'tire_diameter' =>	28.1	,	'min_wheel_width' =>	12.0	,	'max_wheel_width' =>	13.0	}
          ],
          '21' => [
            {	'sku' => 	'14850'	,	'width' =>	255	,	'aspect_ratio' =>	30	,	'weight' =>	25.04	,	'tire_diameter' =>	27.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'5969'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	25.02	,	'tire_diameter' =>	27.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'48747'	,	'width' =>	295	,	'aspect_ratio' =>	25	,	'weight' =>	28.66	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'1604'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	30.73	,	'tire_diameter' =>	28	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ],
          '22' => [
            {	'sku' => 	'4064'	,	'width' =>	235	,	'aspect_ratio' =>	30	,	'weight' =>	23.15	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'19225'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	27.73	,	'tire_diameter' =>	28.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	}
          ]
        }
      },
      'Pilot Sport' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 220,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BSport&cjsku=Michelin+Pilot+Sport+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_sport.csv'
      },
      'Pilot Sport 3' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 320,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BSport%2B3&cjsku=Michelin+Pilot+Sport+3+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_sport_3.csv'
      },
      'Pilot Sport PS2' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 220,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BSport%2BPS2&cjsku=Michelin+Pilot+Sport+PS2+Tire" target="_blank">
                                Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_sport_ps2.csv'
      },
      'Pilot Sport PS2 ZP' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 220,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BSport%2BPS2%2BZP&cjsku=Michelin+Pilot+Sport+PS2+ZP+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_sport_ps2_zp.csv'
      },
      'X-Ice Xi2' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '6w',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DX-Ice%2BXi2&cjsku=Michelin+X-Ice+Xi2+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/xice_xi2.csv'
      },
      'Primacy Alpin PA3' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '5hpw',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPrimacy%2BAlpin%2BPA3&cjsku=Michelin+Primacy+Alpin+PA3+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/primacy_alpin_pa3.csv'
      },
      'Pilot Alpin PA3' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => nil,
        'tire_type' => '5hpw',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BAlpin%2BPA3&cjsku=Michelin+Pilot+Alpin+PA3+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_alpin_pa3.csv'
      },
      'Pilot Alpin PA2' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '5hpw',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BAlpin%2BPA2&cjsku=Michelin+Pilot+Alpin+PA2+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.michelinman.com',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_alpin_pa2.csv'
      },
      'Pilot Sport A/S Plus' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 500,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BSport%2BA%252FS%2BPlus&cjsku=Michelin+Pilot+Sport+A%2FS+Plus+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_sport_as_plus.csv'
      },
      'Pilot Sport A/S Plus ZP' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 500,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BSport%2BA%252FS%2BPlus%2BZP&cjsku=Michelin+Pilot+Sport+A%2FS+Plus+ZP+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_sport_as_plus_zp.csv'
      },
      'Pilot Exalto A/S' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DMichelin%26tireModel%3DPilot%2BExalto%2BA%252FS&cjsku=Michelin+Pilot+Exalto+A%2FS+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/michelin/pilot_exalto_as.csv'
      }
    },
    'Hoosier' => {
      'A6' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => 40,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DHoosier%26tireModel%3DA6&cjsku=Hoosier+A6+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.hoosiertire.com',
        'model_link' => 'http://www.hoosiertire.com/specrr.htm#SPORTS CAR DOT RADIAL',
        'sizes' => {
          '13' => [
            {	'sku' => 	'46307'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	20.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'46310'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	21.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'46320'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	20.9	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}
          ],
          '14' => [
            {	'sku' => 	'46405'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'46415'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	22.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '15' => [
            {	'sku' => 	'46500'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'46510'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	22.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'46535'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	23.0	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ],
          '16' => [
            {	'sku' => 	'46600'	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'46610'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'46615'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'46620'	,	'width' =>	255	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'46630'	,	'width' =>	275	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}
          ],
          '17' => [
            {	'sku' => 	'46705'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	23.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'46710'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'46715'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'46730'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46733'	,	'width' =>	295	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46735'	,	'width' =>	315	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46740'	,	'width' =>	335	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	13.0	}
          ],
          '18' => [
            {	'sku' => 	'46810'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'46820'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'46825'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'46832'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'46836'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46840'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46843'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46844'	,	'width' =>	295	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	27.2	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46846'	,	'width' =>	315	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46850'	,	'width' =>	335	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	12.0	,	'max_wheel_width' =>	13.0	},
            {	'sku' => 	'46855'	,	'width' =>	345	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	13.0	}
          ],
          '19' => [
            {	'sku' => 	'46915'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'46925'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'46935'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46936'	,	'width' =>	295	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.3	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46937'	,	'width' =>	315	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46945'	,	'width' =>	325	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	12.0	,	'max_wheel_width' =>	13.0	},
            {	'sku' => 	'46950'	,	'width' =>	345	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	12.0	,	'max_wheel_width' =>	13.0	}
          ]
        }
      },
      'R6' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => 40,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DHoosier%26tireModel%3DR6&cjsku=Hoosier+R6+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.hoosiertire.com',
        'model_link' => 'http://www.hoosiertire.com/specrr.htm#SPORTS CAR DOT RADIAL',
        'sizes' => {
          '13' => [
            {	'sku' => 	'46300'	,	'width' =>	185	,	'aspect_ratio' =>	60	,	'weight' =>	nil	,	'tire_diameter' =>	21.7	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.0	},
            {	'sku' => 	'46305'	,	'width' =>	205	,	'aspect_ratio' =>	60	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'46307'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	20.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'46310'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	21.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '14' => [
            {	'sku' => 	'46405'	,	'width' =>	205	,	'aspect_ratio' =>	55	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'46410'	,	'width' =>	205	,	'aspect_ratio' =>	60	,	'weight' =>	nil	,	'tire_diameter' =>	23.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'46415'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	22.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '15' => [
            {	'sku' => 	'46500'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'46505'	,	'width' =>	215	,	'aspect_ratio' =>	60	,	'weight' =>	nil	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'46510'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	22.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'46515'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	23.8	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'46525'	,	'width' =>	245	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'46535'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	23.0	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46540'	,	'width' =>	275	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.5	}
          ],
          '16' => [
            {	'sku' => 	'46600'	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	22.8	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'46610'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'46615'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'46620'	,	'width' =>	255	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'46630'	,	'width' =>	275	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}
          ],
          '17' => [
            {	'sku' => 	'46700'	,	'width' =>	205	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	23.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'46705'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	23.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'46710'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'46715'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.5	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'46720'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'46725'	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'46730'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46733'	,	'width' =>	295	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46735'	,	'width' =>	315	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46740'	,	'width' =>	335	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	13.0	}
          ],
          '18' => [
            {	'sku' => 	'46810'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'46820'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'46825'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'46830'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'46832'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'46836'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46840'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46843'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'46844'	,	'width' =>	295	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	27.2	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46846'	,	'width' =>	315	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46850'	,	'width' =>	335	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	12.0	,	'max_wheel_width' =>	13.0	},
            {	'sku' => 	'46855'	,	'width' =>	345	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	13.0	}
          ],
          '19' => [
            {	'sku' => 	'46915'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'46925'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'46935'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46936'	,	'width' =>	295	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	27.3	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46937'	,	'width' =>	315	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46940'	,	'width' =>	315	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	28.9	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	12.0	},
            {	'sku' => 	'46945'	,	'width' =>	325	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	12.0	,	'max_wheel_width' =>	13.0	},
            {	'sku' => 	'46950'	,	'width' =>	345	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	12.0	,	'max_wheel_width' =>	13.0	}
          ]
        }
      }
    },
    'Kumho' => {
      'Ecsta XS' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 180,
        'tire_type' => '1hps',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DKumho%26tireModel%3DEcsta%2BXS&cjsku=Kumho+Ecsta+XS+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://kumhotireusa.com/',
        'model_link' => 'http://kumhotireusa.com/Tire.aspx?id=675dce77-813e-4027-b467-2bea0466bd5c&cat=24',
        'sizes' => {
          '15' => [
            {	'sku' => 	'2106663'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	19.2	,	'tire_diameter' =>	23.1	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	}
          ],
          '16' => [
            {	'sku' => 	'2105703'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	20.0	,	'tire_diameter' =>	23.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'2107913'	,	'width' =>	265	,	'aspect_ratio' =>	45	,	'weight' =>	28.2	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'2105473'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	22.6	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	}
          ],
          '17' => [
            {	'sku' => 	'2105413'	,	'width' =>	295	,	'aspect_ratio' =>	35	,	'weight' =>	29.8	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'2105803'	,	'width' =>	315	,	'aspect_ratio' =>	35	,	'weight' =>	32.4	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	12.5	},
            {	'sku' => 	'2105813'	,	'width' =>	335	,	'aspect_ratio' =>	35	,	'weight' =>	34.4	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	13.0	},
            {	'sku' => 	'2105393'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	25.0	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'2105403'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	25.1	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'2105323'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	27.9	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'2105503'	,	'width' =>	285	,	'aspect_ratio' =>	40	,	'weight' =>	30.2	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'2105443'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	20.7	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'2113963'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	23.5	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'2105453'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	23.9	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'2108103'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	26.7	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	}
          ],
          '18' => [
            {	'sku' => 	'2105823'	,	'width' =>	315	,	'aspect_ratio' =>	30	,	'weight' =>	32.6	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	10.5	,	'max_wheel_width' =>	11.5	},
            {	'sku' => 	'2106703'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	26.2	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'2105183'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	27.2	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'2105493'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	28.2	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'2105343'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	22.9	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'2105283'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	26.6	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'2107203'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	26.6	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'2106553'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	26.6	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	}
          ],
          '19' => [
            {	'sku' => 	'2106113'	,	'width' =>	345	,	'aspect_ratio' =>	30	,	'weight' =>	37.4	,	'tire_diameter' =>	27.2	,	'min_wheel_width' =>	11.5	,	'max_wheel_width' =>	12.5	},
            {	'sku' => 	'2107503'	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	31.4	,	'tire_diameter' =>	26.9	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'Ecsta LE Sport' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DKumho%26tireModel%3DEcsta%2BLE%2BSport&cjsku=Kumho+Ecsta+LE+Sport+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://kumhotireusa.com/',
        'model_link' => '',
        'sizes' => 'tire_data/kumho/ecsta_le_sport.csv'
      },
      'Ecsta ASX' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 420,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DKumho%26tireModel%3DEcsta%2BASX&cjsku=Kumho+Ecsta+ASX+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/kumho/ecsta_asx.csv'
      },
      'Ecsta v700' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 50,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DKumho%26tireModel%3DEcsta%2BV700&cjsku=Kumho+Ecsta+V700+Tire" target="_blank">
                                Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/kumho/ecsta_v700.csv'
      },
      'Ecsta v710' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 30,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DKumho%26tireModel%3DEcsta%2BV710&cjsku=Kumho+Ecsta+V710+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/kumho/ecsta_v710.csv'
      },
      'Ecsta w710' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 30,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DKumho%26tireModel%3DEcsta%2BW710&cjsku=Kumho+Ecsta+W710+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/kumho/ecsta_w710.csv'
      },
      'VictoRacer v700' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 50,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DKumho%26tireModel%3DVictoRacer%2BV700&cjsku=Kumho+VictoRacer+V700+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/kumho/victoracer_v700.csv'
      },
      'Ecsta LS Platinum' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 600,
        'tire_type' => '4a',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DKumho%26tireModel%3DEcsta%2BLX%2BPlatinum&cjsku=Kumho+Ecsta+LX+Platinum+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/kumho/ecsta_lx_platinum.csv'
      },
      'Ecsta AST' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DKumho%26tireModel%3DEcsta%2BAST&cjsku=Kumho+Ecsta+AST+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/kumho/ecsta_ast.csv'
      }
    },
    'Cooper' => {
      'Zeon RS3-S' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 300,
        'tire_type' => '2s',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://us.coopertire.com',
        'model_link' => 'http://us.coopertire.com/Tires/Performance-Tires/ZEON-RS3-S.aspx',
        'sizes' => {
          '17' => [
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	55	,	'weight' =>	nil	,	'tire_diameter' =>	27.1	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ],
          '18' => [
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	27.3	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	nil	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ],
          '19' => [
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	}
          ],
          '20' => [
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	28.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	28.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'Weather-Master WSC' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => nil,
        'tire_type' => '6w',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://us.coopertire.com',
        'model_link' => '',
        'sizes' => 'tire_data/cooper/weather_master_wsc.csv'
      },
      'Weather-Master S/T 2' => {
        'asymmetrical' => false,
        'directional' => false,
        'treadwear' => nil,
        'tire_type' => '6w',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://us.coopertire.com',
        'model_link' => '',
        'sizes' => 'tire_data/cooper/weather_master_st_2.csv'
      },
      'Zeon RS3-A' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 500,
        'tire_type' => '3hpa',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://us.coopertire.com',
        'model_link' => '',
        'sizes' => 'tire_data/cooper/zeon_rs3_a.csv'
      }
    },
    'Federal' => {
      'FZ 201' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 100,
        'tire_type' => '0dotr',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.federaltire.com/',
        'model_link' => 'http://www.federaltire.com/en/html/pdetail.php?DB=motosports&pdline=5&ID=44#',
        'sizes' => {
          '13' => [
            {	'sku' => 	nil	,	'width' =>	185	,	'aspect_ratio' =>	60	,	'weight' =>	nil	,	'tire_diameter' =>	21.7	,	'min_wheel_width' =>	5.0	,	'max_wheel_width' =>	6.5	}
          ],
          '15' => [
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	22.9	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	nil	,	'width' =>	195	,	'aspect_ratio' =>	50	,	'weight' =>	nil	,	'tire_diameter' =>	22.7	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.0	}
          ],
          '17' => [
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.2	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.5	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	}
          ],
          '18' => [
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.2	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	}
          ]
        }
      },
      '595RS-R' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 140,
        'tire_type' => '1hps',
        'tire_rack_link' => '',
        'manufacturer_link' => 'http://www.federaltire.com/',
        'model_link' => 'http://www.federaltire.com/en/html/pdetail.php?DB=motosports&pdline=3&ID=3#',
        'sizes' => {
          '16' => [
            {	'sku' => 	nil	,	'width' =>	205	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	23.2	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	}
          ],
          '17' => [
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	23.7	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	24.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	8.5	}
          ],
          '18' => [
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	nil	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	nil	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	nil	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	nil	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	nil	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	nil	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.0	}
          ]
        }
      }
    },
    'Pirelli' => {
      'PZero System' => {
        'asymmetrical' => nil,
        'directional' => nil,
        'treadwear' => 140,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DPirelli%26tireModel%3DPZero%2BSystem&cjsku=Pirelli+PZero+System+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.us.pirelli.com',
        'model_link' => 'http://www.us.pirelli.com/web/catalog/car-suv-van/catalogo_sd.page?categoria=/catalog/car-suv-van/car/summer&prodotto=876711&uri=/pirellityre/en_US/browser/xml/catalog/car-suv-van/CAR_FITM_PZeroSystem_SUM.xml&vehicleType=CAR-SUV-VAN',
        'sizes' => {
          '15' => [
            {	'sku' => 	nil	,	'width' =>	345,	'aspect_ratio' =>	35,	'weight' =>	34.0	,	'tire_diameter' =>	24.8,	'min_wheel_width' =>	11.5,	'max_wheel_width' =>	13.5,	'asymmetrical' =>	true	,	'directional' =>	false	}
          ],
          '16' => [
            {	'sku' => 	nil	,	'width' =>	205,	'aspect_ratio' =>	55,	'weight' =>	21.0,	'tire_diameter' =>	25.1,	'min_wheel_width' =>	5.5,	'max_wheel_width' =>	7.5	,	'asymmetrical' =>	false,	'directional' =>	false	}
          ],
          '17' => [
            {	'sku' => 	nil	,	'width' =>	205,	'aspect_ratio' =>	45,	'weight' =>	20.0,	'tire_diameter' =>	24.2,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	7.5	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	215,	'aspect_ratio' =>	50,	'weight' =>	24.0,	'tire_diameter' =>	25.7,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.5	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	225,	'aspect_ratio' =>	45,	'weight' =>	23.0,	'tire_diameter' =>	25.1,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	235,	'aspect_ratio' =>	50,	'weight' =>	29.0,	'tire_diameter' =>	26.3,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	245,	'aspect_ratio' =>	50,	'weight' =>	29.0,	'tire_diameter' =>	26.7,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	255,	'aspect_ratio' =>	45,	'weight' =>	27.0,	'tire_diameter' =>	26.1,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	285,	'aspect_ratio' =>	40,	'weight' =>	32.0,	'tire_diameter' =>	26.1,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	335,	'aspect_ratio' =>	35,	'weight' =>	35.0,	'tire_diameter' =>	26.1,	'min_wheel_width' =>	11.0	,	'max_wheel_width' =>	13.0	,	'asymmetrical' =>	true	,	'directional' =>	false	}
          ],
          '18' => [
            {	'sku' => 	nil	,	'width' =>	215,	'aspect_ratio' =>	45,	'weight' =>	24.0,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	,	'asymmetrical' =>	false	,	'directional' =>	true	},
            {	'sku' => 	nil	,	'width' =>	225,	'aspect_ratio' =>	40,	'weight' =>	21.0,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	,	'asymmetrical' =>	false	,	'directional' =>	true	},
            {	'sku' => 	nil	,	'width' =>	235,	'aspect_ratio' =>	35,	'weight' =>	24.0,	'tire_diameter' =>	24.5	,	'min_wheel_width' =>	8.0 ,	'max_wheel_width' =>	9.5	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	245,	'aspect_ratio' =>	40,	'weight' =>	27.0,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	245,	'aspect_ratio' =>	45,	'weight' =>	27.0,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	,	'asymmetrical' =>	false	,	'directional' =>	true	},
            {	'sku' => 	nil	,	'width' =>	255,	'aspect_ratio' =>	40,	'weight' =>	26.0,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	255,	'aspect_ratio' =>	45,	'weight' =>	29.0,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	255,	'aspect_ratio' =>	50,	'weight' =>	31.0,	'tire_diameter' =>	28.1	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	9.0	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	265,	'aspect_ratio' =>	40,	'weight' =>	29.0,	'tire_diameter' =>	26.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	275,	'aspect_ratio' =>	40,	'weight' =>	29.0,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	285,	'aspect_ratio' =>	45,	'weight' =>	34.0,	'tire_diameter' =>	28.1	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	,	'asymmetrical' =>	true	,	'directional' =>	false	}
          ],
          '19' => [
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	27.0	,	'tire_diameter' =>	26.2	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	27.0	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	,	'asymmetrical' =>	true	,	'directional' =>	false	},
            {	'sku' => 	nil	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	30.0	,	'tire_diameter' =>	28.1	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	,	'asymmetrical' =>	true	,	'directional' =>	false	}
          ],
          '20' => [
            {	'sku' => 	nil	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	30.0	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	9.5,	'max_wheel_width' =>	10.5	,	'asymmetrical' =>	true	,	'directional' =>	false	}
          ]
        }
      },
      'PZero' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 220,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DPirelli%26tireModel%3DPZero&cjsku=Pirelli+PZero+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.us.pirelli.com',
        'model_link' => '',
        'sizes' => 'tire_data/pirelli/pzero.csv'
      },
      'PZero RFT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 220,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DPirelli%26tireModel%3DPZero%2BRFT&cjsku=Pirelli+PZero+RFT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.us.pirelli.com',
        'model_link' => '',
        'sizes' => 'tire_data/pirelli/pzero_rft.csv'
      },
      'PZero Nero' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 220,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DPirelli%26tireModel%3DPZero%2BNero&cjsku=Pirelli+PZero+Nero+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.us.pirelli.com',
        'model_link' => '',
        'sizes' => 'tire_data/pirelli/pzero_nero.csv'
      },
      'PZero Rosso' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 220,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DPirelli%26tireModel%3DPZero%2BRosso&cjsku=Pirelli+PZero+Rosso+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.us.pirelli.com',
        'model_link' => '',
        'sizes' => 'tire_data/pirelli/pzero_rosso.csv'
      },
      'PZero Nero All Season' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DPirelli%26tireModel%3DPZero%2BNero%2BAll%2BSeason&cjsku=Pirelli+PZero+Nero+All+Season+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/pirelli/pzero_nero_all_season.csv'
      },
      'PZero Nero All Season RFT' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DPirelli%26tireModel%3DPZero%2BNero%2BAll%2BSeason%2BRFT&cjsku=Pirelli+PZero+Nero+All+Season+RFT+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/pirelli/pzero_nero_all_season_rft.csv'
      },
      'PZero Nero M&S' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 400,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DPirelli%26tireModel%3DPZero%2BNero%2BM%2526S&cjsku=Pirelli+PZero+Nero+M%26S+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/pirelli/pzero_nero_ms.csv'
      },
      'PZero Corsa' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 60,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.jdoqocy.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DPirelli%26tireModel%3DPZero%2BCorsa&cjsku=Pirelli+PZero+Corsa+Tire" target="_blank">
                              Tire Rick</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/pirelli/pzero_corsa.csv'
      },
      'PZero Corsa System' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 60,
        'tire_type' => '0dotr',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DPirelli%26tireModel%3DPZero%2BCorsa%2BSystem&cjsku=Pirelli+PZero+Corsa+System+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/pirelli/pzero_corsa_system.csv'
      }
    },
    'Sumitomo' => {
      'HTR ZIII' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 300,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.anrdoezrs.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DSumitomo%26tireModel%3DHTR%2BZ%2BIII&cjsku=Sumitomo+HTR+Z+III+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.lduhtrp.net/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.sumitomotire.com/cars/',
        'model_link' => 'http://www.sumitomotire.com/cars/products/HTR/htrz3.aspx',
        'sizes' => {
          '17' => [
            {	'sku' => 	'5517905'	,	'width' =>	205	,	'aspect_ratio' =>	50	,	'weight' =>	23.1	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	5.5	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'5517912'	,	'width' =>	215	,	'aspect_ratio' =>	45	,	'weight' =>	22.0	,	'tire_diameter' =>	24.5	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'5517906'	,	'width' =>	215	,	'aspect_ratio' =>	50	,	'weight' =>	22.0	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	7.5	},
            {	'sku' => 	'5517913'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	24.1	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'5517907'	,	'width' =>	225	,	'aspect_ratio' =>	50	,	'weight' =>	22.0	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	6.0	,	'max_wheel_width' =>	8.0	},
            {	'sku' => 	'5517914'	,	'width' =>	235	,	'aspect_ratio' =>	45	,	'weight' =>	23.7	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'5517908'	,	'width' =>	235	,	'aspect_ratio' =>	50	,	'weight' =>	23.7	,	'tire_diameter' =>	26.4	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'5517903'	,	'width' =>	235	,	'aspect_ratio' =>	55	,	'weight' =>	23.7	,	'tire_diameter' =>	27.1	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'5517927'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	26.5	,	'tire_diameter' =>	24.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'5517915'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	27.5	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'5517928'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	25.3	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'5517930'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	29.4	,	'tire_diameter' =>	25.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ],
          '18' => [
            {	'sku' => 	'5517932'	,	'width' =>	215	,	'aspect_ratio' =>	40	,	'weight' =>	21.0	,	'tire_diameter' =>	24.8	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'5517933'	,	'width' =>	225	,	'aspect_ratio' =>	40	,	'weight' =>	25.0	,	'tire_diameter' =>	25.1	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'5517918'	,	'width' =>	225	,	'aspect_ratio' =>	45	,	'weight' =>	22.0	,	'tire_diameter' =>	25.9	,	'min_wheel_width' =>	7.0	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'5517934'	,	'width' =>	235	,	'aspect_ratio' =>	40	,	'weight' =>	23.5	,	'tire_diameter' =>	25.3	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'5517910'	,	'width' =>	235	,	'aspect_ratio' =>	50	,	'weight' =>	23.7	,	'tire_diameter' =>	27.2	,	'min_wheel_width' =>	6.5	,	'max_wheel_width' =>	8.5	},
            {	'sku' => 	'5517935'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	24.3	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'5517920'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	28.0	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'5517949'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	25.6	,	'tire_diameter' =>	25.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'5517936'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	30.5	,	'tire_diameter' =>	26.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'5517921'	,	'width' =>	255	,	'aspect_ratio' =>	45	,	'weight' =>	24.3	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'5517950'	,	'width' =>	265	,	'aspect_ratio' =>	35	,	'weight' =>	27.6	,	'tire_diameter' =>	28.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'5517937'	,	'width' =>	265	,	'aspect_ratio' =>	40	,	'weight' =>	27.6	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'5517951'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	28.5	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'5517938'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	31.6	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'5517970'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	30.8	,	'tire_diameter' =>	24.7	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	},
            {	'sku' => 	'5517952'	,	'width' =>	285	,	'aspect_ratio' =>	35	,	'weight' =>	30.8	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'5517971'	,	'width' =>	295	,	'aspect_ratio' =>	30	,	'weight' =>	29.6	,	'tire_diameter' =>	24.9	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ],
          '19' => [
            {	'sku' => 	'5517956'	,	'width' =>	235	,	'aspect_ratio' =>	35	,	'weight' =>	24.8	,	'tire_diameter' =>	25.4	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'5517957'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	26.0	,	'tire_diameter' =>	25.8	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'5517941'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	26.9	,	'tire_diameter' =>	26.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'5517923'	,	'width' =>	245	,	'aspect_ratio' =>	45	,	'weight' =>	28.9	,	'tire_diameter' =>	27.7	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'5517958'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	25.6	,	'tire_diameter' =>	26.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'5517942'	,	'width' =>	255	,	'aspect_ratio' =>	40	,	'weight' =>	30.5	,	'tire_diameter' =>	27.0	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'5517976'	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	26.7	,	'tire_diameter' =>	25.5	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'5517943'	,	'width' =>	275	,	'aspect_ratio' =>	40	,	'weight' =>	31.6	,	'tire_diameter' =>	27.8	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	}
          ],
          '20' => [
            {	'sku' => 	'5517962'	,	'width' =>	225	,	'aspect_ratio' =>	35	,	'weight' =>	22.0	,	'tire_diameter' =>	26.3	,	'min_wheel_width' =>	7.5	,	'max_wheel_width' =>	9.0	},
            {	'sku' => 	'5517963'	,	'width' =>	245	,	'aspect_ratio' =>	35	,	'weight' =>	27.4	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'5517945'	,	'width' =>	245	,	'aspect_ratio' =>	40	,	'weight' =>	26.9	,	'tire_diameter' =>	27.6	,	'min_wheel_width' =>	8.0	,	'max_wheel_width' =>	9.5	},
            {	'sku' => 	'5517964'	,	'width' =>	255	,	'aspect_ratio' =>	35	,	'weight' =>	27.8	,	'tire_diameter' =>	27.1	,	'min_wheel_width' =>	8.5	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'5517981'	,	'width' =>	275	,	'aspect_ratio' =>	30	,	'weight' =>	31.9	,	'tire_diameter' =>	26.7	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'5517965'	,	'width' =>	275	,	'aspect_ratio' =>	35	,	'weight' =>	34.1	,	'tire_diameter' =>	27.8	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	11.0	},
            {	'sku' => 	'5517982'	,	'width' =>	285	,	'aspect_ratio' =>	30	,	'weight' =>	30.9	,	'tire_diameter' =>	26.8	,	'min_wheel_width' =>	9.5	,	'max_wheel_width' =>	10.5	}
          ],
          '22' => [
            {	'sku' => 	'5517987'	,	'width' =>	265	,	'aspect_ratio' =>	30	,	'weight' =>	24.3	,	'tire_diameter' =>	28.3	,	'min_wheel_width' =>	9.0	,	'max_wheel_width' =>	10.0	},
            {	'sku' => 	'5517992'	,	'width' =>	295	,	'aspect_ratio' =>	25	,	'weight' =>	34.3	,	'tire_diameter' =>	27.9	,	'min_wheel_width' =>	10.0	,	'max_wheel_width' =>	11.0	}
          ]
        }
      },
      'HTR A/S P01' => {
        'asymmetrical' => false,
        'directional' => true,
        'treadwear' => 360,
        'tire_type' => '3hpa',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DSumitomo%26tireModel%3DHTR%2BA%252FS%2BP01%2B%28W%29&cjsku=Sumitomo+HTR+A%2FS+P01+%28W%29+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => '',
        'model_link' => '',
        'sizes' => 'tire_data/sumitomo/htr_as_p01.csv'
      }
    },
    'Continental' => {
      'ContiSportContact 2' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DContinental%26tireModel%3DContiSportContact%2B2&cjsku=Continental+ContiSportContact+2+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.ftjcfx.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.conti-online.com/generator/www/us/en/continental/automobile/general/home/index_en.html',
        'model_link' => '',
        'sizes' => 'tire_data/continental/contisportcontact_2.csv'
      },
      'ContiSportContact 2 SSR' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.tkqlhce.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DContinental%26tireModel%3DContiSportContact%2B2%2BSSR&cjsku=Continental+ContiSportContact+2+SSR+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.conti-online.com/generator/www/us/en/continental/automobile/general/home/index_en.html',
        'model_link' => '',
        'sizes' => 'tire_data/continental/contisportcontact_2_ssr.csv'
      },
      'ContiSportContact 3' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DContinental%26tireModel%3DContiSportContact%2B3&cjsku=Continental+ContiSportContact+3+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.conti-online.com/generator/www/us/en/continental/automobile/general/home/index_en.html',
        'model_link' => '',
        'sizes' => 'tire_data/continental/contisportcontact_3.csv'
      },
      'ContiSportContact 3 SSR' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 280,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DContinental%26tireModel%3DContiSportContact%2B3%2BSSR&cjsku=Continental+ContiSportContact+3+SSR+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.conti-online.com/generator/www/us/en/continental/automobile/general/home/index_en.html',
        'model_link' => '',
        'sizes' => 'tire_data/continental/contisportcontact_3_ssr.csv'
      },
      'ExtremeContact DW ' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => 340,
        'tire_type' => '2s',
        'tire_rack_link' => '<a href="http://www.dpbolvw.net/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DContinental%26tireModel%3DExtremeContact%2BDW&cjsku=Continental+ExtremeContact+DW+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.tqlkg.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.conti-online.com/generator/www/us/en/continental/automobile/general/home/index_en.html',
        'model_link' => '',
        'sizes' => 'tire_data/continental/extremecontact_dw.csv'
      },
      'ExtremeWinterContact' => {
        'asymmetrical' => true,
        'directional' => false,
        'treadwear' => nil,
        'tire_type' => '6w',
        'tire_rack_link' => '<a href="http://www.kqzyfj.com/click-5365183-10398365?url=http%3A%2F%2Fwww.tirerack.com%2Ftires%2Ftires.jsp%3FtireMake%3DContinental%26tireModel%3DExtremeWinterContact&cjsku=Continental+ExtremeWinterContact+Tire" target="_blank">
                              Tire Rack</a><img src="http://www.awltovhc.com/image-5365183-10398365" width="1" height="1" border="0"/>',
        'manufacturer_link' => 'http://www.conti-online.com/generator/www/us/en/continental/automobile/general/home/index_en.html',
        'model_link' => '',
        'sizes' => 'tire_data/continental/extremewintercontact.csv'
      }
    }
  }
end