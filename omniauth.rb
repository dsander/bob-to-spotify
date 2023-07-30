require 'sinatra'
require 'omniauth'
require 'rspotify'
require 'rspotify/oauth'
require "omniauth-deezer"
require 'dotenv'
require 'active_support/all'
require "puma"

Dotenv.load

RSpotify::authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])

module SpotifyOmniauthExtension
  extend ActiveSupport::Concern

  def callback_url
    full_host + script_name + callback_path
  end
end
OmniAuth::Strategies::Spotify.include SpotifyOmniauthExtension

use Rack::Session::Cookie
use OmniAuth::Builder do
  provider :spotify, ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'], scope: 'user-read-email playlist-modify-public playlist-modify-private user-library-read user-library-modify'
  provider :deezer, ENV['DEEZER_CLIENT_ID'], ENV['DEEZER_CLIENT_SECRET'], :perms => 'basic_access,email,manage_library,offline_access,delete_library'

end
configure do
  set :sessions, true
  set :port, 4567
end

get '/' do
  <<-HTML
  <form action='/auth/spotify' method='post'>
    <input type="hidden" name="authenticity_token" value='#{request.env["rack.session"]["csrf"]}'>
    <input type='submit' value='Sign in with Spotify'/>
  </form>
  <form action='/auth/deezer' method='post'>
    <input type="hidden" name="authenticity_token" value='#{request.env["rack.session"]["csrf"]}'>
    <input type='submit' value='Sign in with Deezer'/>
  </form>
  HTML
end

get '/auth/spotify/callback' do
  auth = request.env['omniauth.auth']
  spotify_user = RSpotify::User.new(request.env['omniauth.auth'])
  pp spotify_user

  "SPOTIFY_USER_CREDENTIALS=#{Base64.strict_encode64(spotify_user.to_hash.to_json)}"
end

get '/auth/deezer/callback' do
  auth = request.env['omniauth.auth']
  pp auth["credentials"]["token"]

  "DEEZER_TOKEN=#{auth["credentials"]["token"]}"
end

get '/auth/failure' do
  "FAILED"
end
