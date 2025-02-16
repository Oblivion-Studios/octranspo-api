require 'faraday'
require 'nokogiri'
require './time'

class Hash
  def join(inner=$,, outer=$,)
    map { |e| e.join(inner) }.join(outer)
  end
end

class Live
  def initialize(app_id, api_key)
    @app_id = app_id
    @api_key = api_key
    @conn = Faraday.new('https://api.octranspo1.com')
    @mappings = {
      :next_for_route => {
        'TripDestination'     => { :key => :destination, :conv => lambda { |s| s } },
        'TripStartTime'       => { :key => :departure_from_origin, :conv => lambda { |s| hour_and_minutes_to_elapsed(s) } },
        'AdjustedScheduleTime'=> { :key => :expected, :conv => lambda { |s| secs_elapsed_today + 60 * s.to_i } },
        'AdjustmentAge'       => { :key => :age, :conv => lambda { |s| '-1' == s ? nil : (s.to_f * 60).to_i } },
        'BusType'             => { :key => :bus_type, :conv => lambda { |s| s } },
        'Latitude'            => { :key => :latitude, :conv => lambda { |s| s.to_f } },
        'Longitude'           => { :key => :longitude, :conv => lambda { |s| s.to_f } },
        'GPSSpeed'            => { :key => :approximate_speed, :conv => lambda { |s| s.to_f } },
      },
      :route_summary => {
        'RouteNo'      => { :key => :route_no, :conv => lambda { |s| s.to_i } },
        'DirectionID'  => { :key => :direction_id, :conv => lambda { |s| s.to_i } },
        'Direction'    => { :key => :direction, :conv => lambda { |s| s } },
        'RouteHeading' => { :key => :heading, :conv => lambda { |s| s } },
      }
   }
  end

  def update_pickups(stop_no, pickups)
    adjustments = {}
    counters = {}
    # this is complicated b/c our pickups only contain a time window
    # the remote live call gives us much more. therefore we try to
    # merge the results into the original pickups. we assume that we're
    # getting the results from the live system in the same order
    # as those in the pickups array
    pickups.collect { |v| v[:trip][:route] }.uniq.each do |route_no|
      next_for_route(stop_no, route_no) do |vals|
        adjustments[route_no] = vals
        counters[route_no] = 0
      end
    end

    pickups.collect do |old_vals|
      vals = old_vals.clone
      route_no = vals[:trip][:route]
      live = adjustments[route_no][counters[route_no]]
      vals[:arrival_difference] = vals[:arrival] - live[:expected]
      vals[:arrival] = live[:expected]
      vals[:live] = {
        :departure_from_origin => live[:departure_from_origin],
        :age                   => live[:age],
        :location              => {
          :lat                   => live[:latitude],
          :lon                   => live[:longitude],
          :approximate_speed     => live[:approximate_speed],
        },
      }
      vals[:scheduled_arrival] = vals[:arrival]
      counters[route_no] += 1
      vals
    end if adjustments.length
  end

  def arrivals(stop_no, route_no)
    rv = []
    next_for_route(stop_no, route_no) do |vals|
      rv = vals
    end
    rv
  end

  def routes(stop_no)
    rv = []
    # BUG: docs have <RoutesForStopData> as root node; running system yields <GetRouteSummaryForStopResult>
    request('GetRouteSummaryForStop', 'GetRouteSummaryForStopResult', { 'stopNo' => stop_no }) do |root_node|
      # BUG: we seem to get Routes/Route/node in cases of multiple routes, but Routes/Route in
      # cases of single routes; therefore, do both and concatenate
      multi = root_node.css('Routes/Route/node').collect do |pn|
        apply_mapping(:route_summary, pn, { :stop_no => stop_no })
      end
      single = root_node.css('Routes/Route').collect do |pn|
        apply_mapping(:route_summary, pn, { :stop_no => stop_no })
      end
      rv = multi + single
    end
    rv
  end

  def request(op, root, payload)
    payload['appID'] = @app_id
    payload['apiKey'] = @api_key
    payload['format'] = 'xml'
    resp = @conn.get("/v2.0/#{op}") do |req|
      req.params = payload
    end
    doc = Nokogiri::XML(resp.body, nil, 'utf-8')
    doc.remove_namespaces!
    yield(doc.css(root))
  end

  def apply_mapping(key, node, vals)
    @mappings[key].each do |k, v|
      n = node.css(k.to_s)
      vals[v[:key].to_sym] = v[:conv].call(n.first.content) if n
    end
    vals
  end

  def next_for_route(stop_no, route_no)
    # BUG: docs have <StopInfoData> as root node; running system yields <GetNextTripsForStopResult>
    request('GetNextTripsForStop', 'GetNextTripsForStopResult', { 'stopNo' => stop_no, 'routeNo' => route_no }) do |root_node|
      multi = root_node.css('Trips/Trip/node').collect do |pn|
        apply_mapping(:next_for_route, pn, { :stop_no => stop_no, :route_no => route_no })
      end
      single = root_node.css('Trips/Trip').collect do |pn|
        apply_mapping(:next_for_route, pn, { :stop_no => stop_no, :route_no => route_no })
      end
      yield(multi + single)
    end
  end
end
