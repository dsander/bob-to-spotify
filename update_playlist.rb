require 'net/http'
require 'active_support/all'
require 'rspotify'
require 'dotenv'
require 'vcr'

Dotenv.load

VCR.configure do |c|
  c.default_cassette_options = { record: :new_episodes }
  c.hook_into :webmock
  c.cassette_library_dir = 'cassettes'
  c.allow_http_connections_when_no_cassette = true
end

class PlaylistDownloader
  def initialize(station:, day:)
    @station = station
    @day = day
  end

  def entries
    entries = []
    (0..21).step(3) do |offset|
      entries << get_playlist(start: day + offset.hours, stop: day + offset.hours + 3.hours)
    end
    entries.flatten.uniq.map { |e| PlayListSong.new(e) }.sort
  end

  private

  attr_accessor :station, :day

  def get_playlist(start:, stop:)
    uri = URI('https://iris-bob.loverad.io/search.json')
    params = { station: station, start: start.iso8601, end: stop.iso8601}
    uri.query = URI.encode_www_form(params)

    res = Net::HTTP.get_response(uri)
    raise "Failed to fetch data: '#{res.code}' '#{res.body}'" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body).with_indifferent_access.fetch(:result).fetch(:entry)
  end
end

class PlayListSong
  include Comparable

  attr_reader :title, :artist, :album, :airtime

  def initialize(entry)
    song = entry.dig(:song, :entry).first
    @title = song.fetch(:title)
    @artist = song.fetch(:artist).fetch(:entry).first.fetch(:name)
    @album = song.fetch(:collection_name)
    @airtime = Time.parse(entry.fetch(:airtime))
  end

  def <=>(other)
    airtime <=> other.airtime
  end
end

entries = VCR.use_cassette('playlist_download') do
  PlaylistDownloader.new(station: 69, day: Date.yesterday).entries
end

tracks = []
VCR.use_cassette('track_matching') do
  RSpotify::authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])

  entries.each do |entry|
    puts "#{entry.airtime} - #{entry.artist} - #{entry.album} - #{entry.title}"

    found_tracks = RSpotify::Track.search("#{entry.artist} #{entry.title}", limit: 5, market: 'DE')
    if found_tracks.length == 0
      puts "Not found :("
    else
      track = found_tracks.first
      puts "#{entry.airtime} - #{track.artists.map(&:name).join(', ')} - #{track.album.name} - #{track.name}: #{track.is_playable}"
      tracks << track
    end
  end
end

VCR.use_cassette('playlist_update') do
  RSpotify::authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])
  user = RSpotify::User.new(JSON.parse(Base64.decode64(ENV['SPOTIFY_USER_CREDENTIALS'])))
  RSpotify::User.send(:refresh_token, user.id)
  puts "Emtpying playlist ..."
  while (playlist = RSpotify::Playlist.find(user.display_name, ENV['SPOTIFY_PLAYLIST'])).tracks.length > 0
    puts playlist.tracks.length
    playlist.remove_tracks!(playlist.tracks)
  end

  puts 'Filling playlist ...'
  tracks.in_groups_of(50, false).each do |group|
    playlist.add_tracks!(group)
  end
end
