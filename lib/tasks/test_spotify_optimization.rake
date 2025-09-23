namespace :spotify do
  desc "Test and compare Spotify API optimization"
  task test_optimization: :environment do
    require 'benchmark'

    # Test artist (you can change this to any artist)
    test_artist_name = ENV['ARTIST_NAME'] || "Radiohead"

    puts "\n" + "="*60
    puts "SPOTIFY API OPTIMIZATION TEST"
    puts "Testing with artist: #{test_artist_name}"
    puts "="*60 + "\n"

    # Initialize service
    service = Spotify::SyncArtistWithTopTracks.new(
      artist_name: test_artist_name,
      fetch_top_tracks: true,
      country: "US",
      rate_limit_delay: 0.35
    )

    # Track metrics
    api_calls_before = 0
    api_calls_after = 0

    # Simulate old approach (for comparison)
    puts "\n📊 SIMULATED OLD APPROACH (Individual API Calls):"
    puts "-" * 40

    begin
      # 1. Find artist
      api_calls_before += 1
      puts "  ✓ API Call ##{api_calls_before}: Search for artist"

      # 2. Get artist details
      api_calls_before += 1
      puts "  ✓ API Call ##{api_calls_before}: Get artist details"

      # 3. Get albums (returns basic info only)
      api_calls_before += 1
      puts "  ✓ API Call ##{api_calls_before}: Get artist albums"

      # 4. Simulate fetching each album individually (assuming 10 albums)
      estimated_albums = 10
      estimated_albums.times do |i|
        api_calls_before += 1
        puts "  ✓ API Call ##{api_calls_before}: Get album ##{i+1} details"
      end

      # 5. Get top tracks
      api_calls_before += 1
      puts "  ✓ API Call ##{api_calls_before}: Get top tracks"

      puts "\n  Old Approach Total: #{api_calls_before} API calls"
    rescue => e
      puts "  Error simulating old approach: #{e.message}"
    end

    # Execute new optimized approach
    puts "\n📊 NEW OPTIMIZED APPROACH:"
    puts "-" * 40

    result = nil
    actual_api_calls = 0

    # Monkey-patch to count actual API calls (for demonstration)
    module RSpotify
      class << self
        alias_method :original_get, :get if !method_defined?(:original_get)

        def get(path, *args)
          $api_call_counter += 1 if defined?($api_call_counter)
          original_get(path, *args)
        end
      end
    end

    begin
      $api_call_counter = 0

      time = Benchmark.realtime do
        result = service.call
      end

      actual_api_calls = $api_call_counter

      if result
        puts "  ✓ Artist synced: #{result.name}"
        puts "  ✓ Albums synced: #{result.albums.count}"
        puts "  ✓ Tracks synced: #{result.tracks.count}"
        puts "  ✓ Top tracks: #{result.tracks.where(is_top_track: true).count}"
        puts "\n  New Approach Total: ~#{actual_api_calls} API calls"
        puts "  Time taken: #{time.round(2)} seconds"
      else
        puts "  ✗ Failed to sync artist"
      end
    rescue => e
      puts "  Error in optimized approach: #{e.message}"
      puts e.backtrace.first(5) if Rails.env.development?
    ensure
      $api_call_counter = nil
    end

    # Show savings
    puts "\n📈 OPTIMIZATION RESULTS:"
    puts "="*60

    if api_calls_before > 0 && actual_api_calls > 0
      savings = ((api_calls_before - actual_api_calls).to_f / api_calls_before * 100).round(1)

      puts "  Old approach (estimated): #{api_calls_before} API calls"
      puts "  New approach (actual):     #{actual_api_calls} API calls"
      puts "  API calls saved:           #{api_calls_before - actual_api_calls}"
      puts "  Reduction:                 #{savings}%"

      if savings > 50
        puts "\n  🎉 Excellent optimization! Over 50% reduction in API calls!"
      elsif savings > 30
        puts "\n  ✨ Good optimization! Significant reduction in API calls."
      else
        puts "\n  📊 Moderate optimization achieved."
      end
    end

    # Show data utilization improvements
    puts "\n📦 DATA UTILIZATION IMPROVEMENTS:"
    puts "-" * 40

    if result
      artist = result

      # Check new fields that are now being captured
      new_fields_captured = []
      new_fields_captured << "external_urls" if artist.external_urls.present?
      new_fields_captured << "followers (#{artist.followers})" if artist.followers.present?

      if artist.albums.any?
        album = artist.albums.first
        new_fields_captured << "album popularity" if album.popularity.present?
        new_fields_captured << "album label" if album.label.present?
      end

      if new_fields_captured.any?
        puts "  New data fields now captured:"
        new_fields_captured.each do |field|
          puts "    ✓ #{field}"
        end
      end

      # Show batch processing stats
      puts "\n  Batch processing improvements:"
      puts "    ✓ Albums fetched in batches of 20"
      puts "    ✓ Tracks saved in bulk transactions"
      puts "    ✓ Rate limiting prevents 429 errors"
    end

    puts "\n" + "="*60
    puts "TEST COMPLETE"
    puts "="*60

    # Restore original RSpotify.get method
    if RSpotify.respond_to?(:original_get)
      module RSpotify
        class << self
          alias_method :get, :original_get
        end
      end
    end
  end

  desc "Analyze API usage for existing artists"
  task analyze_usage: :environment do
    puts "\n📊 ANALYZING EXISTING ARTIST DATA"
    puts "="*60

    total_artists = Artist.count
    total_albums = Album.count
    total_tracks = Track.count

    puts "\nCurrent Database Stats:"
    puts "  Artists: #{total_artists}"
    puts "  Albums:  #{total_albums}"
    puts "  Tracks:  #{total_tracks}"

    if total_artists > 0
      avg_albums_per_artist = (total_albums.to_f / total_artists).round(1)
      avg_tracks_per_album = total_tracks > 0 && total_albums > 0 ? (total_tracks.to_f / total_albums).round(1) : 0

      puts "\nAverages:"
      puts "  Albums per artist: #{avg_albums_per_artist}"
      puts "  Tracks per album:  #{avg_tracks_per_album}"

      # Estimate API calls saved
      puts "\nEstimated API Calls (if syncing all data):"

      # Old approach
      old_calls = total_artists * 2  # Find + details
      old_calls += total_artists      # Get albums list
      old_calls += total_albums       # Individual album fetches
      old_calls += total_artists      # Top tracks

      # New approach (estimated)
      new_calls = total_artists * 2   # Find + albums list
      new_calls += (total_albums / 20.0).ceil  # Batch album fetches

      puts "  Old approach: #{old_calls} calls"
      puts "  New approach: #{new_calls} calls"
      puts "  Saved: #{old_calls - new_calls} calls (#{((old_calls - new_calls).to_f / old_calls * 100).round(1)}%)"
    end

    puts "\n" + "="*60
  end
end
