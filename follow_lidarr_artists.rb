require "rest-client"
require "json"
require "rspotify"
require "dotenv"

Dotenv.load

# Lidarr and Spotify API credentials
LIDARR_URL = "#{ENV.fetch("LIDARR_URL")}/api/v1" # Replace with your Lidarr URL

# Authenticate with Spotify API
RSpotify::authenticate(ENV["SPOTIFY_CLIENT_ID"], ENV["SPOTIFY_CLIENT_SECRET"])

def fetch_lidarr_tags
  url = "#{LIDARR_URL}/tag"
  headers = { "X-Api-Key" => ENV.fetch("LIDARR_API_KEY") }
  response = RestClient.get(url, headers)
  tags = JSON.parse(response.body)

  # Map tags into a hash for easy lookup by ID
  tags.each_with_object({}) { |tag, hash| hash[tag["id"]] = tag["label"] }
end

def lidarr_get_artists_without_spotify_tag(tags_hash)
  url = "#{LIDARR_URL}/artist"
  headers = { "X-Api-Key" => ENV.fetch("LIDARR_API_KEY") }
  response = RestClient.get(url, headers)
  artists = JSON.parse(response.body)

  # Filter artists without the "spotify" tag
  artists.reject do |artist|
    artist.fetch("tags").any? { |tag_id| tags_hash[tag_id] == "spotify" }
  end
end

def get_spotify_artist_id(name)
  results = RSpotify::Artist.search(name)
  results.first&.id # Return the ID of the first match
end

def follow_artist_on_spotify(user, spotify_artist_id)
  puts "Following artist with ID: #{spotify_artist_id}"
  user.follow(RSpotify::Artist.find(spotify_artist_id), public: false)
end

def main
  user = RSpotify::User.new(JSON.parse(Base64.decode64(ENV["SPOTIFY_USER_CREDENTIALS"])))
  RSpotify::User.send(:refresh_token, user.id)

  puts "Fetching tags from Lidarr..."
  tags_hash = fetch_lidarr_tags
  puts "Fetched #{tags_hash.size} tags."

  puts "Fetching artists without Spotify tag from Lidarr..."
  artists = lidarr_get_artists_without_spotify_tag(tags_hash)

  puts "Found #{artists.size} artists without Spotify tag. Processing..."

  artists.each do |artist|
    name = artist['artistName']
    puts "Looking up Spotify artist for: #{name}"

    spotify_url = artist.fetch("links").find { |link| link.fetch("name") == "spotify" }&.fetch("url")

    spotify_artist_id = spotify_url && URI(spotify_url).path.split('/').last
    spotify_artist_id ||= get_spotify_artist_id(name)

    if spotify_artist_id
      puts "Found Spotify artist ID: #{spotify_artist_id}. Following..."

      follow_artist_on_spotify(user, spotify_artist_id)
    else
      puts "Could not find Spotify artist for: #{name}"
    end
  end

  puts 'Done!'
end

main
