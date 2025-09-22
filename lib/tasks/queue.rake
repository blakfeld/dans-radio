namespace :queue do
  desc "Start queue processing job"
  task start: :environment do
    puts "Starting queue processing..."
    ProcessRequestQueueJob.start_processing
    puts "Queue processing started!"
  end

  desc "Stop queue processing job"
  task stop: :environment do
    puts "Stopping queue processing..."
    ProcessRequestQueueJob.stop_processing
    puts "Queue processing stopped!"
  end

  desc "Show queue status"
  task status: :environment do
    queue = RequestQueue.get

    if queue
      puts "=" * 50
      puts "Queue Status for Radio Station"
      puts "=" * 50
      puts "Playlist: #{queue.playlist_name} (ID: #{queue.playlist_id})"
      puts "Sync Status: #{queue.sync_status}"
      puts "Last Sync: #{queue.last_sync_at&.strftime('%Y-%m-%d %H:%M:%S')}"
      puts ""

      if queue.current_track
        puts "Currently Playing: #{queue.current_track.title} by #{queue.current_track.artist&.name}"
      else
        puts "Currently Playing: Nothing"
      end

      if queue.next_track
        puts "Next Up: #{queue.next_track.title} by #{queue.next_track.artist&.name}"
      else
        puts "Next Up: Nothing"
      end

      puts ""
      puts "Queue Contents (#{queue.song_requests.active.count} tracks):"
      puts "-" * 50

      queue.song_requests.active.order(:position).each_with_index do |request, index|
        status_icon = case request.status
        when "playing" then "▶️"
        when "queued" then "✅"
        when "pending" then "⏳"
        else "❓"
        end

        track = request.track
        if track
          puts "#{index + 1}. #{status_icon} #{track.title} by #{track.artist&.name} (#{request.status})"
        else
          puts "#{index + 1}. #{status_icon} Unknown Track (#{request.status})"
        end
      end
    else
      puts "No active queue found"
    end
  end

  desc "Sync queue with Spotify"
  task sync: :environment do
    puts "Syncing queue with Spotify..."
    result = GetQueuePosition.call

    if result[:success]
      puts "✅ Queue synced successfully!"
      puts "Current Track: #{result[:current_track]&.title || 'None'}"
      puts "Next Track: #{result[:next_track]&.title || 'None'}"
      puts "Sync Status: #{result[:sync_status]}"
    else
      puts "❌ Sync failed: #{result[:error]}"
    end
  end

  desc "Clear the queue"
  task clear: :environment do
    print "Are you sure you want to clear the queue? (y/n): "
    response = STDIN.gets.chomp.downcase

    if response == "y"
      result = ClearSongRequestQueue.call
      if result[:success]
        puts "✅ Queue cleared successfully!"
      else
        puts "❌ Failed to clear queue: #{result[:error]}"
      end
    else
      puts "Cancelled"
    end
  end

  desc "Add a test track to the queue"
  task :add_test_track, [ :spotify_id ] => :environment do |t, args|
    spotify_id = args[:spotify_id] || "3n3Ppam7vgaVa1iaRUc9Lp" # Mr. Brightside as default

    puts "Adding track #{spotify_id} to queue..."

    track = Track.find_by_spotify_id(spotify_id)
    unless track
      puts "Track not found in database, fetching from Spotify..."
      spotify_track = RSpotify::Track.find(spotify_id)
      track = Track.create_from_spotify(spotify_track)
    end

    if track
      result = EnqueueSongRequest.call(track: track)
      if result[:success]
        puts "✅ #{result[:message]}"
      else
        puts "❌ Failed: #{result[:error]}"
      end
    else
      puts "❌ Could not find or create track"
    end
  end

  desc "Recover queue from Spotify playlist"
  task recover: :environment do
    queue = RequestQueue.get

    if queue
      puts "Attempting to recover queue from Spotify playlist..."
      if queue.recover_from_spotify!
        puts "✅ Queue recovered successfully!"
        Rake::Task["queue:status"].invoke
      else
        puts "❌ Failed to recover queue"
      end
    else
      puts "No active queue found"
    end
  end
end
