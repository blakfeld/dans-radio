namespace :spotify do
  desc "Refresh Spotify OAuth tokens for all users"
  task refresh_tokens: :environment do
    puts "Refreshing Spotify OAuth tokens..."
    puts "-" * 50

    SpotifyUser.all.each do |user|
      print "User: #{user.username.ljust(20)}"

      if !user.refresh_token.present?
        puts "❌ No refresh token"
        next
      end

      if user.token_expired?
        print "🔴 Token expired - "
      elsif user.token_expiring_soon?
        print "🟡 Token expiring soon - "
      else
        puts "✅ Token valid until #{user.expires_at.strftime('%Y-%m-%d %H:%M')}"
        next
      end

      if user.refresh_access_token!
        puts "✅ Refreshed! New expiry: #{user.reload.expires_at.strftime('%Y-%m-%d %H:%M')}"
      else
        puts "❌ Failed to refresh"
      end
    end

    puts "-" * 50
    puts "Token refresh complete."
  end

  desc "Benchmark sync performance with optimization metrics"
  task :benchmark_sync, [ :playlist_name ] => :environment do |t, args|
    playlist_name = args[:playlist_name] || "Dan's Radio"

    puts "=" * 60
    puts "Benchmarking Sync Performance"
    puts "Playlist: #{playlist_name}"
    puts "=" * 60

    # Track API calls by monkey-patching (temporary for benchmark)
    api_calls = 0
    original_get = RSpotify.method(:get)
    RSpotify.define_singleton_method(:get) do |path, *args|
      api_calls += 1
      original_get.call(path, *args)
    end

    # Track database operations
    db_operations = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      db_operations += 1 if args[4][:sql] =~ /INSERT|UPDATE|DELETE/i
    end

    begin
      start_time = Time.current

      result = Spotify::SyncPlaylistTracks.call(
        playlist_name: playlist_name,
        sync_full_artist_catalog: true,
        rate_limit_delay: 0.5
      ) do |info, index, total|
        if info.is_a?(String)
          print "\r#{info}" + " " * 20
        elsif info.respond_to?(:name)
          print "\r[#{index + 1}/#{total}] Processing: #{info.name[0..40]}..."
        end
      end

      elapsed = Time.current - start_time
      print "\r" + " " * 80 + "\r"

      if result[:success]
        puts "\n✅ Benchmark Complete!\n"
        puts "📊 Performance Metrics:"
        puts "  Time elapsed: #{elapsed.round(2)} seconds"
        puts "  API calls: #{api_calls}"
        puts "  DB operations: #{db_operations}"
        puts "\n📈 Sync Results:"
        puts "  Playlist tracks: #{result[:playlist_tracks_count]}"
        puts "  Unique artists: #{result[:unique_artists_count]}"
        puts "  Total tracks synced: #{result[:synced_tracks_count]}"
        puts "  Total albums synced: #{result[:synced_albums_count]}"
        puts "  Top tracks synced: #{result[:top_tracks_count] || 0}"
        puts "\n🎯 Efficiency:"
        puts "  API calls per track: #{(api_calls.to_f / result[:synced_tracks_count]).round(3)}" if result[:synced_tracks_count] > 0
        puts "  DB ops per track: #{(db_operations.to_f / result[:synced_tracks_count]).round(3)}" if result[:synced_tracks_count] > 0
        puts "  Tracks/second: #{(result[:synced_tracks_count] / elapsed).round(2)}" if elapsed > 0
      else
        puts "❌ Benchmark failed: #{result[:error]}"
      end
    ensure
      # Restore original method
      RSpotify.define_singleton_method(:get, original_get)
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    puts "=" * 60
  end

  desc "Check token status for all Spotify users"
  task token_status: :environment do
    puts "Spotify OAuth Token Status"
    puts "=" * 50

    if SpotifyUser.count == 0
      puts "No authenticated Spotify users found."
      puts "Visit http://localhost:3000/setup to authenticate."
      exit
    end

    SpotifyUser.all.each do |user|
      puts "\nUser: #{user.username}"
      puts "  Email: #{user.email || 'N/A'}"
      puts "  Token: #{user.token.present? ? user.token[0..20] + '...' : 'Missing'}"
      puts "  Refresh Token: #{user.refresh_token.present? ? 'Present' : 'Missing'}"

      if user.expires_at
        time_left = user.expires_at - Time.current
        if time_left > 0
          hours = (time_left / 3600).to_i
          minutes = ((time_left % 3600) / 60).to_i
          puts "  Expires: #{user.expires_at.strftime('%Y-%m-%d %H:%M:%S')} (#{hours}h #{minutes}m remaining)"

          if user.token_expiring_soon?
            puts "  Status: 🟡 Expiring Soon"
          else
            puts "  Status: ✅ Valid"
          end
        else
          puts "  Expires: #{user.expires_at.strftime('%Y-%m-%d %H:%M:%S')} (Expired)"
          puts "  Status: 🔴 Expired"
        end
      else
        puts "  Expires: Unknown"
        puts "  Status: ❓ Unknown"
      end
    end

    puts "\n" + "=" * 50
    puts "Run 'rails spotify:refresh_tokens' to refresh expired tokens."
  end
  desc "Search for playlists by name"
  task :search_playlists, [ :query ] => :environment do |t, args|
    query = args[:query]

    if query.blank?
      puts "Please provide a search query"
      puts "Usage: rails spotify:search_playlists[\"search term\"]"
      exit 1
    end

    puts "Searching for playlists matching: #{query}..."
    puts "-" * 50

    begin
      # Try to get authenticated user first
      spotify_user = SpotifyUser.find_by(username: Rails.application.config.spotify[:user_name])

      if spotify_user
        # Search user's own playlists
        user = spotify_user.to_rspotify_user
        user_playlists = user.playlists(limit: 50)
        matching_playlists = user_playlists.select { |p| p.name.downcase.include?(query.downcase) }

        if matching_playlists.any?
          puts "\n🎵 Your Playlists:"
          matching_playlists.each do |playlist|
            puts "\n   Name: #{playlist.name}"
            puts "   ID: #{playlist.id}"
            puts "   Tracks: #{playlist.total}"
            puts "   Public: #{playlist.public ? 'Yes' : 'No'}"
            puts "   Owner: #{playlist.owner.display_name || playlist.owner.id}"
          end
        end
      end

      # Also search public playlists
      puts "\n🌍 Public Playlists:"
      public_playlists = RSpotify::Playlist.search(query, limit: 20)

      if public_playlists.any?
        public_playlists.each do |playlist|
          puts "\n   Name: #{playlist.name}"
          puts "   ID: #{playlist.id}"
          puts "   Tracks: #{playlist.total}"
          puts "   Owner: #{playlist.owner.display_name || playlist.owner.id}"
          puts "   Description: #{playlist.description[0..100] if playlist.description}#{'...' if playlist.description && playlist.description.length > 100}"
        end
      else
        puts "   No public playlists found"
      end

      puts "\n" + "-" * 50
      puts "To sync a playlist, use:"
      puts "  rails spotify:sync_playlist_tracks[\"Playlist Name\"]"
      puts "Or by ID:"
      puts "  rails spotify:sync_playlist_by_id[PLAYLIST_ID]"

    rescue => e
      puts "❌ Error: #{e.message}"
      puts e.backtrace.first(5) if Rails.env.development?
      exit 1
    end
  end

  desc "Sync all tracks from a playlist to the local database (optionally sync all artist catalogs)"
  task :sync_playlist_tracks, [ :playlist_name, :sync_full_catalog, :rate_limit ] => :environment do |t, args|
    playlist_name = args[:playlist_name]
    sync_full_catalog = args[:sync_full_catalog] != "false" # Default to true unless explicitly 'false'
    rate_limit_delay = args[:rate_limit]&.to_f || 0.5 # Default to 2 req/sec

    if playlist_name.blank?
      puts "Please provide a playlist name"
      puts "Usage: rails spotify:sync_playlist_tracks[\"Playlist Name\"]"
      puts "       rails spotify:sync_playlist_tracks[\"Playlist Name\",false]  # Only sync playlist tracks"
      puts "       rails spotify:sync_playlist_tracks[\"Playlist Name\",true,0.5]  # Custom rate limit (2 req/sec)"
      exit 1
    end

    puts "Searching for playlist: #{playlist_name}..."
    puts "Sync mode: #{sync_full_catalog ? 'Full artist catalog with top tracks' : 'Playlist tracks only'}"
    puts "Rate limit: #{(1.0 / rate_limit_delay).round(2)} requests/second (applies to API calls only)" if rate_limit_delay > 0
    puts "-" * 50
    puts "\nSync will run in two phases:"
    puts "  Phase 1: Quick sync of playlist tracks (no API calls, very fast)"
    puts "  Phase 2: Fetch full artist catalogs + top 5 tracks (API calls with rate limiting)" if sync_full_catalog
    puts "-" * 50

    # Create a custom progress tracking block
    current_track = 0
    result = Spotify::SyncPlaylistTracks.call(
      playlist_name: playlist_name,
      sync_full_artist_catalog: sync_full_catalog,
      rate_limit_delay: rate_limit_delay
    ) do |info, index, total|
      # Handle both track objects and string messages
      if info.respond_to?(:name)
        current_track = index + 1
        print "\r[#{current_track}/#{total}] Processing: #{info.name[0..50]}#{'...' if info.name.length > 50}"
      else
        print "\r#{info}" + " " * 20 # Add padding to clear previous text
      end
    end

    # Clear the progress line
    print "\r" + " " * 80 + "\r" if current_track > 0

    if result[:success]
      puts "✅ Found playlist: #{result[:playlist_name]}"
      puts "-" * 50
      puts "\n✅ Sync completed!"
      puts "📊 Summary:"
      puts "   - Playlist tracks: #{result[:playlist_tracks_count]}"
      puts "   - Unique artists found: #{result[:unique_artists_count]}"
      puts "   - Total tracks synced: #{result[:synced_tracks_count]}"
      puts "   - Total albums synced: #{result[:synced_albums_count]}"
      puts "   - Total artists synced: #{result[:synced_artists_count]}"
      puts "   - Top tracks synced: #{result[:top_tracks_count]}"
      puts "   - Errors: #{result[:error_count]}"

      if result[:errors].any?
        puts "\n⚠️  Errors encountered:"
        result[:errors].first(10).each do |error|
          puts "   - #{error}"
        end
        puts "   ... and #{result[:errors].length - 10} more" if result[:errors].length > 10
      end

      puts "\n📊 Database Statistics:"
      puts "   - Artists in database: #{result[:stats][:artists]}"
      puts "   - Albums in database: #{result[:stats][:albums]}"
      puts "   - Tracks in database: #{result[:stats][:tracks]}"
      puts "   - Top tracks in database: #{result[:stats][:top_tracks]}"
    else
      puts "❌ #{result[:error]}"
      puts result[:backtrace] if result[:backtrace]
      exit 1
    end
  end

  desc "Test the find_by_spotify_id methods"
  task :test_find_or_fetch, [ :spotify_id, :type ] => :environment do |t, args|
    spotify_id = args[:spotify_id]
    type = args[:type] || "track"

    if spotify_id.blank?
      puts "Please provide a Spotify ID and optionally a type (track, album, or artist)"
      puts "Usage: rails spotify:test_find_or_fetch[SPOTIFY_ID,TYPE]"
      puts "Example: rails spotify:test_find_or_fetch[3n3Ppam7vgaVa1iaRUc9Lp,track]"
      exit 1
    end

    puts "Testing find_by_spotify_id for #{type}: #{spotify_id}"
    puts "-" * 50

    begin
      case type.downcase
      when "artist"
        puts "🎤 Fetching Artist..."
        artist = Artist.find_by_spotify_id(spotify_id)
        if artist
          puts "✅ Artist found/fetched: #{artist.name}"
          puts "   - Database ID: #{artist.id}"
          puts "   - Spotify ID: #{artist.spotify_id}"
          puts "   - URI: #{artist.uri}"
          puts "   - Images: #{artist.images&.length || 0} image(s)"
        else
          puts "❌ Artist not found"
        end

      when "album"
        puts "💿 Fetching Album..."
        album = Album.find_by_spotify_id(spotify_id)
        if album
          puts "✅ Album found/fetched: #{album.name}"
          puts "   - Database ID: #{album.id}"
          puts "   - Spotify ID: #{album.spotify_id}"
          puts "   - Artist: #{album.artist&.name}"
          puts "   - Type: #{album.album_type}"
          puts "   - Release Date: #{album.release_date}"
          puts "   - Total Tracks: #{album.total_tracks}"
          puts "   - Images: #{album.images&.length || 0} image(s)"
        else
          puts "❌ Album not found"
        end

      when "track"
        puts "🎵 Fetching Track..."
        track = Track.find_by_spotify_id(spotify_id)
        if track
          puts "✅ Track found/fetched: #{track.title}"
          puts "   - Database ID: #{track.id}"
          puts "   - Spotify ID: #{track.spotify_id}"
          puts "   - Album: #{track.album&.name}"
          puts "   - Artist: #{track.artist&.name}"
          puts "   - Duration: #{track.duration_formatted}"
          puts "   - Track Number: #{track.track_number}"
          puts "   - Explicit: #{track.explicit ? 'Yes' : 'No'}"
          puts "   - Playable: #{track.is_playable ? 'Yes' : 'No'}"
          puts "   - Preview URL: #{track.preview_url.present? ? 'Available' : 'Not available'}"
        else
          puts "❌ Track not found"
        end

      else
        puts "❌ Invalid type: #{type}"
        puts "Valid types are: track, album, artist"
      end

      puts "-" * 50
      puts "\n📊 Database Statistics:"
      puts "   - Artists: #{Artist.count}"
      puts "   - Albums: #{Album.count}"
      puts "   - Tracks: #{Track.count}"

    rescue => e
      puts "❌ Error: #{e.message}"
      puts e.backtrace.first(5) if Rails.env.development?
      exit 1
    end
  end

  desc "Sync playlist by Spotify ID (works without authentication for public playlists)"
  task :sync_playlist_by_id, [ :playlist_id ] => :environment do |t, args|
    playlist_id = args[:playlist_id]

    if playlist_id.blank?
      puts "Please provide a playlist ID"
      puts "Usage: rails spotify:sync_playlist_by_id[PLAYLIST_ID]"
      puts "You can find playlist IDs using: rails spotify:search_playlists[\"search term\"]"
      exit 1
    end

    puts "Fetching playlist with ID: #{playlist_id}..."

    begin
      # Directly fetch playlist by ID - works for public playlists without auth
      playlist = RSpotify::Playlist.find(playlist_id)

      if playlist
        puts "✅ Found playlist: #{playlist.name}"
        puts "   Owner: #{playlist.owner.display_name || playlist.owner.id}"
        puts "   Total tracks: #{playlist.total}"
        puts "-" * 50

        # Use the existing sync service logic
        synced_count = 0
        error_count = 0
        errors = []

        # Fetch all tracks
        all_tracks = []
        offset = 0
        limit = 100

        while offset < playlist.total
          tracks = playlist.tracks(limit: limit, offset: offset)
          all_tracks.concat(tracks)
          offset += limit
        end

        # Sync tracks
        all_tracks.each_with_index do |track, index|
          print "\r[#{index + 1}/#{all_tracks.length}] Processing: #{track.name[0..50]}#{'...' if track.name.length > 50}"

          begin
            ActiveRecord::Base.transaction do
              # Sync artist
              if track.artists.any?
                primary_artist = track.artists.first
                artist_record = Artist.find_or_initialize_by(spotify_id: primary_artist.id)
                artist_record.assign_attributes(
                  name: primary_artist.name,
                  images: primary_artist.images,
                  uri: primary_artist.uri,
                  href: primary_artist.href
                )
                artist_record.save! if artist_record.changed?

                # Sync album
                if track.album
                  album_record = Album.find_or_initialize_by(spotify_id: track.album.id)
                  album_record.assign_attributes(
                    name: track.album.name,
                    artist_id: artist_record.id,
                    album_type: track.album.album_type,
                    total_tracks: track.album.total_tracks,
                    external_urls: track.album.external_urls,
                    href: track.album.href,
                    images: track.album.images,
                    release_date: track.album.release_date,
                    uri: track.album.uri
                  )
                  album_record.save! if album_record.changed?

                  # Sync track
                  track_record = Track.find_or_initialize_by(spotify_id: track.id)
                  track_record.assign_attributes(
                    title: track.name,
                    album_id: album_record.id,
                    duration_ms: track.duration_ms,
                    explicit: track.explicit,
                    href: track.href,
                    is_playable: track.is_playable,
                    preview_url: track.preview_url,
                    track_number: track.track_number,
                    uri: track.uri
                  )
                  track_record.save! if track_record.changed?
                  synced_count += 1
                end
              end
            end
          rescue => e
            error_count += 1
            errors << "Error syncing '#{track.name}': #{e.message}"
          end
        end

        # Clear progress line
        print "\r" + " " * 80 + "\r"

        puts "\n✅ Sync completed!"
        puts "📊 Summary:"
        puts "   - Total tracks processed: #{all_tracks.length}"
        puts "   - Successfully synced: #{synced_count}"
        puts "   - Errors: #{error_count}"

        if errors.any?
          puts "\n⚠️  Errors encountered:"
          errors.first(10).each do |error|
            puts "   - #{error}"
          end
          puts "   ... and #{errors.length - 10} more" if errors.length > 10
        end

        puts "\n📊 Database Statistics:"
        puts "   - Artists in database: #{Artist.count}"
        puts "   - Albums in database: #{Album.count}"
        puts "   - Tracks in database: #{Track.count}"
      else
        puts "❌ Playlist not found or not accessible"
        exit 1
      end
    rescue => e
      puts "❌ Error: #{e.message}"
      puts e.backtrace.first(5) if Rails.env.development?
      exit 1
    end
  end
end
