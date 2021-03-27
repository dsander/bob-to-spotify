require 'net/http'
require 'active_support/all'
require 'rspotify'
require 'dotenv'

Dotenv.load

def get_playlist(station:, start:, stop:)
  uri = URI('https://iris-bob.loverad.io/search.json')
  params = { station: station, start: start.iso8601, end: stop.iso8601}
  uri.query = URI.encode_www_form(params)
  cache_key =  Base64::strict_encode64(uri.to_s)
  FileUtils.mkdir_p('cache')
  cache_file = File.join('cache', cache_key)
  data = if File.exists?(cache_file)
           File.read(cache_file)
         else
           res = Net::HTTP.get_response(uri)
           raise "Failed to fetch data: '#{res.code}' '#{res.body}'" unless res.is_a?(Net::HTTPSuccess)

           File.open(cache_file, 'w') do |f|
             f.write(res.body)
           end
           res.body
         end
  JSON.parse(data).with_indifferent_access.fetch(:result).fetch(:entry)
end

def get_daily_playlist(station:, day:)
  entries = []
  (0..21).step(3) do |offset|
    entries << get_playlist(station: 69, start: day + offset.hours, stop: day + offset.hours + 3.hours)
  end
  entries.flatten.uniq.sort_by { |e| Time.parse(e.fetch(:airtime))}
end

entries = get_daily_playlist(station: 69, day: Date.yesterday)
# entries = get_playlist(station: 69, start: Time.now.yesterday.beginning_of_day, stop: Time.now.yesterday.beginning_of_day + 3.hour)
# playlist = get_playlist(station: 69, start: Time.now.yesterday.beginning_of_day + 3.hour, stop: Time.now.yesterday.beginning_of_day + 6.hour)
# playlist = get_playlist(station: 69, start: Time.now.yesterday.beginning_of_day + 6.hour, stop: Time.now.yesterday.beginning_of_day + 9.hour)

RSpotify::authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])

tracks = []
entries.each do |entry|
  song = entry.dig(:song, :entry).first

  title = song.fetch(:title)

  artist = song.fetch(:artist).fetch(:entry).first.fetch(:name)
  album = song.fetch(:collection_name)

  puts "#{Time.parse(entry.fetch(:airtime))} - #{artist} - #{album} - #{title}"
  found_tracks = RSpotify::Track.search("#{artist} #{title}", limit: 1, market: 'DE')
  if found_tracks.length == 0
    puts "Not found :("
  else
    track = found_tracks.first
    puts "#{track.artists.map(&:name).join(', ')} - #{track.album.name} - #{track.name}: #{track.is_playable}"
    tracks << track
  end
end

RSpotify::User.new(JSON.parse(Base64.decode64(ENV['SPOTIFY_USER_CREDENTIALS'])))

playlist = RSpotify::Playlist.find('dsander', '5DdQD9CqqAPdiyKtdvKEwL')
while playlist.tracks.length > 0
  playlist.remove_tracks!(playlist.tracks)
  pp playlist.tracks.length
end
tracks.in_groups_of(50, false).each do |group|
  pp group
  playlist.add_tracks!(group)
end
pp playlist
