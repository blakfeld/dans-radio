class ProcessRequestQueueJob < ApplicationJob
  queue_as :critical

  # This job runs periodically to sync queue state with Spotify
  # and process any pending requests

  def perform
    # Get the singleton queue
    request_queue = RequestQueue.get

    return log_no_queue unless request_queue

    begin
      # First, sync our queue position with Spotify
      sync_result = GetQueuePosition.call(request_queue: request_queue)

      if sync_result[:error]
        Rails.logger.error "Queue sync failed: #{sync_result[:error]}"
        return schedule_retry(10.seconds)
      end

      # Process based on sync status
      case request_queue.sync_status
      when "out_of_sync"
        handle_out_of_sync(request_queue)
      when "recovering"
        Rails.logger.info "Queue is recovering, will retry soon"
        schedule_next_check(5.seconds)
      when "synced"
        process_queue(request_queue, sync_result)
      end

    rescue StandardError => e
      Rails.logger.error "ProcessRequestQueueJob failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      schedule_retry(30.seconds)
    end
  end

  private

  def process_queue(request_queue, sync_result)
    # Check if we need to add more tracks to Spotify
    ensure_spotify_queue_filled(request_queue)

    # Process any pending requests that need to be queued
    process_pending_requests(request_queue)

    # Schedule next check based on current playing state
    if sync_result[:currently_playing_spotify] && sync_result[:currently_playing_spotify][:is_playing]
      # Calculate when current track should finish
      track = sync_result[:current_track]
      if track && track.duration_ms
        progress_ms = sync_result[:currently_playing_spotify][:progress_ms] || 0
        remaining_ms = track.duration_ms - progress_ms
        remaining_seconds = [ remaining_ms / 1000.0, 1 ].max # At least 1 second

        Rails.logger.info "Current track has #{remaining_seconds}s remaining, scheduling next check"
        schedule_next_check(remaining_seconds.seconds)
      else
        # Check again in 30 seconds if we can't determine track duration
        schedule_next_check(30.seconds)
      end
    else
      # Nothing playing, check again in 1 minute
      Rails.logger.info "No track playing, checking again in 1 minute"
      schedule_next_check(1.minute)
    end
  end

  def ensure_spotify_queue_filled(request_queue)
    # Get pending requests that haven't been added to Spotify yet
    pending_requests = request_queue.song_requests
                                    .where(status: "pending")
                                    .order(:position)
                                    .limit(5) # Add up to 5 tracks at a time

    pending_requests.each do |song_request|
      begin
        # Add track to Spotify playlist
        track = song_request.track
        next unless track

        spotify_track = track.to_rspotify_track
        next unless spotify_track

        # Get the spotify user and playlist
        username = Rails.application.config.spotify[:user_name]

        if request_queue.playlist_id
          playlist = RSpotify::Playlist.find(username, request_queue.playlist_id)
          playlist.add_tracks!([ spotify_track ])

          song_request.update!(
            status: "queued",
            queued_at: Time.current
          )

          Rails.logger.info "Added #{track.title} to Spotify playlist"
        else
          # No playlist, try direct queue
          Spotify::QueueSong.call(spotify_track)
          song_request.update!(
            status: "queued",
            queued_at: Time.current
          )

          Rails.logger.info "Queued #{track.title} directly to Spotify"
        end

      rescue => e
        Rails.logger.error "Failed to queue track #{song_request.id}: #{e.message}"
        song_request.update!(status: "failed", state: e.message)
      end
    end
  end

  def process_pending_requests(request_queue)
    # Update positions if needed
    request_queue.send(:reorder_positions)

    # Update next track reference
    next_track = request_queue.next_up
    request_queue.update!(next_track: next_track) if request_queue.next_track != next_track
  end

  def handle_out_of_sync(request_queue)
    Rails.logger.warn "Queue #{request_queue.id} is out of sync, attempting recovery"

    if request_queue.recover_from_spotify!
      Rails.logger.info "Queue recovered successfully"
      schedule_next_check(5.seconds)
    else
      Rails.logger.error "Failed to recover queue, will retry in 1 minute"
      schedule_retry(1.minute)
    end
  end

  def log_no_queue
    Rails.logger.info "No active request queue found"
    nil
  end

  def schedule_next_check(wait_time)
    ProcessRequestQueueJob.set(wait: wait_time).perform_later
    Rails.logger.info "Next queue check scheduled in #{wait_time}"
  end

  def schedule_retry(wait_time)
    ProcessRequestQueueJob.set(wait: wait_time).perform_later
    Rails.logger.info "Retrying queue processing in #{wait_time}"
  end

  # Class method to start the queue processing
  def self.start_processing
    # Cancel any existing scheduled jobs
    # Note: This depends on your job backend (Sidekiq, SolidQueue, etc.)
    # For SolidQueue:
    if defined?(SolidQueue)
      SolidQueue::ScheduledExecution.joins(:job)
        .where(solid_queue_jobs: { class_name: "ProcessRequestQueueJob" })
        .where("scheduled_at > ?", Time.current)
        .destroy_all
    end

    # Start processing immediately
    perform_later
    Rails.logger.info "Started queue processing"
  end

  def self.stop_processing
    # Cancel scheduled jobs
    if defined?(SolidQueue)
      SolidQueue::ScheduledExecution.joins(:job)
        .where(solid_queue_jobs: { class_name: "ProcessRequestQueueJob" })
        .destroy_all
    end

    Rails.logger.info "Stopped queue processing"
  end
end
