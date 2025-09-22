namespace :test do
  desc "Test fetching top tracks for an artist"
  task :top_tracks, [ :artist_name ] => :environment do |t, args|
    artist_name = args[:artist_name] || "Taylor Swift"

    puts "🎵 Testing top tracks for: #{artist_name}"
    puts "-" * 50

    # Find or create the artist
    artist = Artist.joins(:albums).find_by(name: artist_name)

    if artist
      puts "✅ Found existing artist: #{artist.name}"
    else
      puts "🔍 Searching for artist on Spotify..."
      results = RSpotify::Artist.search(artist_name, limit: 1)

      if results.any?
        spotify_artist = results.first
        artist = Artist.create!(
          spotify_id: spotify_artist.id,
          name: spotify_artist.name,
          images: spotify_artist.images,
          uri: spotify_artist.uri,
          href: spotify_artist.href,
          genres: spotify_artist.genres,
          popularity: spotify_artist.popularity
        )
        puts "✅ Created artist: #{artist.name}"
      else
        puts "❌ Artist not found on Spotify"
        exit
      end
    end

    # Fetch top tracks
    puts "\n📊 Fetching top tracks from Spotify..."
    top_tracks = artist.fetch_and_cache_top_tracks(limit: 10, country: "US")

    if top_tracks.any?
      puts "✅ Successfully fetched #{top_tracks.count} top tracks:"
      puts ""
      top_tracks.each_with_index do |track, index|
        puts "  #{index + 1}. #{track.title}"
        puts "     Album: #{track.album&.name}"
        puts "     Duration: #{track.duration_formatted}"
        puts "     Popularity: #{track.popularity}/100"
        puts "     Top Track: #{track.is_top_track? ? '✅' : '❌'}"
        puts ""
      end
    else
      puts "❌ No top tracks found"
    end

    # Show cached top tracks
    puts "\n📦 Cached top tracks in database:"
    cached_tracks = artist.top_tracks(limit: 5)
    cached_tracks.each_with_index do |track, index|
      puts "  #{index + 1}. #{track.title} (Popularity: #{track.popularity})"
    end
  end

  desc "Sync an artist with albums and top tracks"
  task :sync_artist, [ :artist_name ] => :environment do |t, args|
    artist_name = args[:artist_name]

    unless artist_name
      puts "Please provide an artist name"
      puts "Usage: rails test:sync_artist['Artist Name']"
      exit
    end

    puts "🎵 Syncing artist: #{artist_name}"
    puts "-" * 50

    service = Spotify::SyncArtistWithTopTracks.new(
      artist_name: artist_name,
      fetch_top_tracks: true
    )

    artist = service.call

    if artist
      puts "✅ Successfully synced artist: #{artist.name}"
      puts "   Albums: #{artist.albums.count}"
      puts "   Total Tracks: #{artist.tracks.count}"
      puts "   Top Tracks: #{artist.tracks.where(is_top_track: true).count}"
      puts "   Genres: #{artist.genres&.join(', ')}"
      puts "   Popularity: #{artist.popularity}/100"
    else
      puts "❌ Failed to sync artist"
    end
  end
end
