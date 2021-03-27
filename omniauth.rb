require 'sinatra'
require 'omniauth'
require 'rspotify'
require 'rspotify/oauth'
require 'dotenv'
require 'active_support/all'

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
end

get '/' do
  <<-HTML
  <form action='/auth/spotify' method='post'>
    <input type="hidden" name="authenticity_token" value="#{env['rack.session'][:csrf]}" />
    <input type='submit' value='Sign in with Spotify'/>
  </form>
  HTML
end

get '/auth/spotify/callback' do
  auth = request.env['omniauth.auth']
  spotify_user = RSpotify::User.new(request.env['omniauth.auth'])
  pp spotify_user

  "SPOTIFY_USER_CREDENTIALS=#{Base64.strict_encode64(spotify_user.to_hash.to_json)}"
end

get '/auth/failure' do
  "FAILED"
end
