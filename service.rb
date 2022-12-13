require 'json'
require 'sinatra'
require 'rdiscount'
require './model'
require './lib'
require './live'
require './location'

## STOPS ##
def show_all_stops
  # complete list of stops, no period
  content_type :json
  Stop.all.to_json
end

get '/stops' do
  show_all_stops
end

get '/stops/' do
  show_all_stops
end

get '/stops/:number' do
  content_type :json
  Stop.first(:number => params[:number].to_i).to_json
end

def show_nearby(it, meters)
  it.nearby(meters).to_json
end

def show_closest(it)
  it.nearby().first.to_json
end

get '/stops/:number/nearby' do
  meters = (params.key?('within')) ? params['within'].to_i : 400
  content_type :json
  show_nearby(Stop.first(:number => params[:number].to_i), meters)
end

get '/stops/:number/nearby/closest' do
  content_type :json
  show_closest(Stop.first(:number => params[:number].to_i))
end

get '/stops/:number/routes' do
  content_type :json
  Stop.first(:number => params[:number].to_i).routes(false).to_json
end

get '/stops/:number/routes/in_service' do
  content_type :json
  Stop.first(:number => params[:number].to_i).routes(true).to_json
end

get '/stops_by_name/:name' do
  content_type :json
  Stop.all(:name.like => "%#{params[:name].upcase}%").to_json
end

get '/stops_nearby/:lat/:lon' do
  meters = (params.key?('within')) ? params['within'].to_i : 400
  content_type :json
  show_nearby(Coords.new(params[:lat].to_f, params[:lon].to_f), meters)
end

get '/stops_nearby/:lat/:lon/closest' do
  content_type :json
  show_closest(Coords.new(params[:lat].to_f, params[:lon].to_f))
end

## TRAVEL ##
get '/arrivals/:stop_number' do
  minutes = (params.key?('minutes')) ? params[:minutes].to_i : 15
  num = params[:stop_number].to_i

  content_type :json
  pickups = Pickup.arriving_at_stop(num, minutes).collect { |pi| pi.humanize }

  # has the client given us some live api fuel? if so, let's try to merge it!
  if params.key? 'app_id' and params.key? 'api_key'
    pickups = Live.new(params['app_id'], params['api_key']).update_pickups(num, pickups)
  end
  pickups.to_json
end

get '/destinations/:trip_id/:sequence' do
  range = (params.key?('range')) ? params[:range].to_i : 10
  trip_id = params[:trip_id].to_i
  seq = params[:sequence].to_i

  content_type :json
  pi = Pickup.first(:trip_id => trip_id, :sequence => seq)
  pi.next_in_sequence(range).collect { |npi| npi.humanize }.to_json
end

## LIVE ##
get '/live/routes/:stop_id' do
  rv = []
  if params.key? 'app_id' and params.key? 'api_key'
    rv = Live.new(params['app_id'], params['api_key']).routes(params[:stop_id])
  end
  content_type :json
  rv.to_json
end

get '/live/arrivals/:stop_no/:route_no' do
  rv = []
  if params.key? 'app_id' and params.key? 'api_key'
    rv = Live.new(params['app_id'], params['api_key']).arrivals(params[:stop_no], params[:route_no])
  end
  content_type :json
  rv.to_json
end

## DEFAULTS ##
get '/' do
  markdown :readme
end

get '/version' do
  ver = Version.first
  content_type :json
  { :api => API_VERSION, :schema => ver.schema_version, :feed => ver.feed_version }.to_json
end

not_found do
  content_type :json
  { :error => 'not_found' }.to_json
end
