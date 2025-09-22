namespace :radio do
  desc "Manually ensure the radio is playing the correct playlist"
  task ensure_playlist: :environment do
    puts "Running UpdateStateJob..."
    result = UpdateStateJob.perform_now
    puts "Job completed successfully"
  end

  desc "Manually sync the queue playlist with internal state"
  task sync_queue: :environment do
    puts "Running SyncQueuePlaylistJob..."
    SyncQueuePlaylistJob.perform_now
    puts "Queue playlist synced successfully"
  end

  desc "Force rebuild the queue playlist from internal state"
  task rebuild_queue: :environment do
    puts "Force rebuilding queue playlist..."
    SyncQueuePlaylistJob.perform_now(force_rebuild: true)
    puts "Queue playlist rebuilt successfully"
  end

  desc "Show current radio and queue status"
  task status: :environment do
    queue = RequestQueue.get

    puts "\n=== Radio Status ==="
    puts "Queue Playlist: #{queue.playlist_name}"
    puts "Playlist ID: #{queue.playlist_id}"
    puts "Sync Status: #{queue.sync_status}"
    puts "Last Sync: #{queue.last_sync_at || 'Never'}"
    puts "Active: #{queue.active?}"

    puts "\n=== Queue Contents ==="
    puts "Total Requests: #{queue.song_requests.count}"
    puts "Pending: #{queue.song_requests.where(status: 'pending').count}"
    puts "Queued: #{queue.song_requests.where(status: 'queued').count}"
    puts "Playing: #{queue.song_requests.where(status: 'playing').count}"
    puts "Played: #{queue.song_requests.where(status: 'played').count}"

    if queue.current_track
      puts "\n=== Currently Playing ==="
      puts "Track: #{queue.current_track.title}"
      puts "Artist: #{queue.current_track.artist&.name}"
    end

    if queue.next_up
      puts "\n=== Next Up ==="
      puts "Track: #{queue.next_up.title}"
      puts "Artist: #{queue.next_up.artist&.name}"
    end

    puts "\n=== Upcoming Tracks ==="
    queue.upcoming_tracks(limit: 5).each_with_index do |track, index|
      if track
        puts "#{index + 1}. #{track.title} - #{track.artist&.name}"
      else
        puts "#{index + 1}. (No track)"
      end
    end

    # Check what Spotify is actually playing
    currently_playing = Spotify::GetCurrentlyPlaying.call
    if currently_playing
      puts "\n=== Spotify Status ==="
      puts "Playing: #{currently_playing[:is_playing]}"
      if currently_playing[:track]
        puts "Track: #{currently_playing[:track].name}"
        puts "Artist: #{currently_playing[:track].artists&.first&.name}"
      end
      puts "Context URI: #{currently_playing[:context_uri]}"
    end
  end

  desc "Test the radio playlist switching logic"
  task test_switching: :environment do
    queue = RequestQueue.get

    puts "Testing playlist switching logic..."

    # Check current state
    result = ManageCurrentlyPlaying.call(request_queue: queue)
    puts "Current state: #{result.inspect}"

    if result[:error]
      puts "Error occurred: #{result[:error]}"
    elsif result[:changed]
      puts "Playlist was changed to: #{result[:playlist]}"
    else
      puts "Already playing correct playlist: #{result[:playlist]}"
    end
  end
end
