namespace :demo do
  desc "Search and add popular artists to the database for demo purposes"
  task add_popular_artists: :environment do
    # List of popular artists to search for
    artists_to_search = [
      "Taylor Swift",
      "The Weeknd",
      "Ed Sheeran",
      "Drake",
      "Billie Eilish",
      "Post Malone",
      "Ariana Grande",
      "Dua Lipa",
      "Bruno Mars",
      "Olivia Rodrigo",
      "Doja Cat",
      "The Beatles",
      "Queen",
      "Pink Floyd",
      "Led Zeppelin",
      "Radiohead",
      "Arctic Monkeys",
      "Kendrick Lamar",
      "Kanye West",
      "Beyoncé"
    ]

    puts "🎵 Adding popular artists to database..."
    puts "-" * 50

    success_count = 0
    error_count = 0

    artists_to_search.each do |artist_name|
      print "Searching for #{artist_name.ljust(20)}: "

      begin
        # Search for the artist
        results = RSpotify::Artist.search(artist_name, limit: 1)

        if results.any?
          spotify_artist = results.first

          # Check if artist already exists
          existing = Artist.find_by(spotify_id: spotify_artist.id)
          if existing
            puts "✅ Already exists"
            next
          end

          # Create the artist
          artist = Artist.create!(
            spotify_id: spotify_artist.id,
            name: spotify_artist.name,
            images: spotify_artist.images,
            uri: spotify_artist.uri,
            href: spotify_artist.href,
            genres: spotify_artist.genres,
            popularity: spotify_artist.popularity
          )

          # Fetch and cache top tracks
          artist.fetch_and_cache_top_tracks(limit: 5, country: "US")

          # Fetch and create some albums
          albums = spotify_artist.albums(limit: 5, country: "US")
          albums.each do |spotify_album|
            album = Album.find_or_create_by(spotify_id: spotify_album.id) do |a|
              a.name = spotify_album.name
              a.artist_id = artist.id
              a.album_type = spotify_album.album_type
              a.total_tracks = spotify_album.total_tracks
              a.external_urls = spotify_album.external_urls
              a.href = spotify_album.href
              a.images = spotify_album.images
              a.release_date = spotify_album.release_date
              a.uri = spotify_album.uri
            end

            # Add a few tracks from each album
            if album.persisted?
              album_full = RSpotify::Album.find(spotify_album.id)
              album_full.tracks(limit: 5).each do |spotify_track|
                Track.find_or_create_by(spotify_id: spotify_track.id) do |t|
                  t.title = spotify_track.name
                  t.album_id = album.id
                  t.duration_ms = spotify_track.duration_ms
                  t.explicit = spotify_track.explicit
                  t.href = spotify_track.href
                  t.is_playable = spotify_track.is_playable
                  t.preview_url = spotify_track.preview_url
                  t.track_number = spotify_track.track_number
                  t.uri = spotify_track.uri
                end
              end
            end
          end

          puts "✅ Added with #{albums.count} albums"
          success_count += 1
        else
          puts "❌ Not found"
          error_count += 1
        end
      rescue => e
        puts "❌ Error: #{e.message}"
        error_count += 1
      end
    end

    puts "-" * 50
    puts "✅ Successfully added: #{success_count} artists"
    puts "❌ Failed: #{error_count} artists" if error_count > 0
    puts "\n📊 Database now contains:"
    puts "   Artists: #{Artist.count}"
    puts "   Albums: #{Album.count}"
    puts "   Tracks: #{Track.count}"
  end

  desc "Clear all demo data"
  task clear: :environment do
    print "Are you sure you want to delete all artists, albums, and tracks? (y/n): "
    response = STDIN.gets.chomp.downcase

    if response == "y"
      Track.destroy_all
      Album.destroy_all
      Artist.destroy_all
      puts "✅ All demo data cleared"
    else
      puts "❌ Cancelled"
    end
  end

  desc "Search for artists by genre"
  task :search_genre, [ :genre ] => :environment do |t, args|
    genre = args[:genre]

    if genre.blank?
      puts "Please provide a genre"
      puts "Usage: rails demo:search_genre[rock]"
      exit
    end

    puts "🎵 Searching for #{genre} artists..."
    puts "-" * 50

    begin
      # Search for playlists of this genre to find artists
      playlists = RSpotify::Playlist.search(genre, limit: 5)
      artists_found = Set.new

      playlists.each do |playlist|
        begin
          playlist.tracks(limit: 20).each do |track|
            next unless track && track.artists.any?

            artist = track.artists.first
            next if artists_found.include?(artist.id)

            artists_found.add(artist.id)

            # Try to create the artist
            existing = Artist.find_by(spotify_id: artist.id)
            unless existing
              Artist.create!(
                spotify_id: artist.id,
                name: artist.name,
                images: artist.images || [],
                uri: artist.uri,
                href: artist.href
              )
              puts "✅ Added: #{artist.name}"
            end
          end
        rescue => e
          puts "⚠️ Error processing playlist: #{e.message}"
        end

        break if artists_found.size >= 10
      end

      puts "-" * 50
      puts "Found #{artists_found.size} unique artists"

    rescue => e
      puts "❌ Error: #{e.message}"
    end
  end
end
