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

    sanitized = res.body.gsub(/,{[^}]*,,/, ",")
    JSON.parse(sanitized).with_indifferent_access.fetch(:result).fetch(:entry)
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

class DeezerClient
  class DeezerError < StandardError; end

  class Track
    include Comparable

    attr_reader :id, :title, :artist, :album, :link

    def initialize(track)
      @id = track.fetch(:id)
      @title = track.fetch(:title)
      @artist = track.fetch(:artist).fetch(:name)
      @album = track.fetch(:album).fetch(:title)
      @link = track.fetch(:link)
    end

    def hash
      id
    end

    def eql?(other)
      id == other.id
    end
  end

  class << self
    def search(track:, artist:)
      uri = URI('https://api.deezer.com/search')
      # params = { q: "artist:\"#{artist}\" track:\"#{track}\"", limit: 1 }
      params = { q: "#{artist} - #{track}", limit: 1 }
      uri.query = URI.encode_www_form(params)

      res = Net::HTTP.get_response(uri)
      if res.is_a?(Net::HTTPForbidden)
        puts "Got HTTPForbidden, skipping"
        return nil
      end
      raise "Failed to fetch data: '#{res.code}' '#{res.body}'" unless res.is_a?(Net::HTTPSuccess)

      handle_response(res).map { |t| Track.new(t) }.first
    end

    def playlist_tracks
      uri = URI("https://api.deezer.com/playlist/#{ENV['DEEZER_PLAYLIST']}/tracks")
      uri.query = params

      res = Net::HTTP.get_response(uri)

      handle_response(res).map { |t| Track.new(t) }
    end

    def delete_tracks_from_playlist(tracks:)
      return true if tracks.empty?

      uri = URI("https://api.deezer.com/playlist/#{ENV['DEEZER_PLAYLIST']}/tracks")

      uri.query = params({ songs: tracks.map(&:id).join(',') })
      res = Net::HTTP.new(uri.hostname).delete(uri.request_uri)
      handle_response(res)
    end

    def set_playlist_tracks(tracks:)
      uri = URI("https://api.deezer.com/playlist/#{ENV['DEEZER_PLAYLIST']}/tracks")
      uri.query = params({ songs: tracks.map(&:id).join(',') })

      res = Net::HTTP.post_form(uri, {})
      handle_response(res)
    end

    private

    def params(hash = {})
      URI.encode_www_form(hash.merge(access_token: ENV.fetch("DEEZER_TOKEN")))
    end


    def handle_response(res)
      raise DeezerError.new("Failed to fetch data: '#{res.code}' '#{res.body}'") unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body)
      return data if data == true
      data = data.with_indifferent_access

      raise DeezerError.new("#{data.dig(:error, :type)}: #{data.dig(:error, :message)}") if data.key?(:error)

      data.fetch(:data)
    end
  end
end

tracks = []
VCR.use_cassette('track_matching_deezer') do
  entries.each do |entry|
    puts "#{entry.airtime} - #{entry.artist} - #{entry.album} - #{entry.title}"

    track = DeezerClient.search(track: entry.title, artist: entry.artist)
    unless track
      puts "Not found :("
      puts "#{entry.airtime} - #{entry.artist} - #{entry.album} - #{entry.title}"
    else
      puts "#{entry.airtime} - #{track.artist} - #{track.album} - #{track.title}"
      tracks << track
    end
  end
end

puts "Emtpying playlist ..."
while (current_tracks = DeezerClient.playlist_tracks).length > 0
  DeezerClient.delete_tracks_from_playlist(tracks: current_tracks)
end
tracks.uniq!
puts 'Filling playlist ...'
DeezerClient.set_playlist_tracks(tracks: tracks)
