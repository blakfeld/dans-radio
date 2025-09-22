class UpdateStateJob < ApplicationJob
  queue_as :high_priority

  # This job ensures the radio is playing the correct playlist based on the queue state
  # It runs every minute to check and switch playlists if needed

  def perform
    Rails.logger.info "[UpdateStateJob] Starting radio state update"

    # Get the request queue singleton
    request_queue = RequestQueue.get

    # Update the playhead first - this tracks what's currently playing
    playhead_result = UpdatePlayhead.call(request_queue: request_queue)
    if playhead_result[:updated]
      Rails.logger.info "[UpdateStateJob] Playhead updated: #{playhead_result[:current_track]} at position #{playhead_result[:current_position]}"
    else
      Rails.logger.debug "[UpdateStateJob] Playhead not updated: #{playhead_result[:reason]}"
    end

    # Check if queue is empty and we should auto-start radio
    active_count = request_queue.song_requests.where(status: [ "playing", "queued", "pending" ]).count
    auto_start_radio = active_count == 0

    # Use the ManageCurrentlyPlaying service to ensure correct playlist is playing
    result = ManageCurrentlyPlaying.call(request_queue: request_queue, auto_start: auto_start_radio)

    # Log the outcome
    if result[:error]
      Rails.logger.error "[UpdateStateJob] Error managing playlist: #{result[:error]}"
    elsif result[:auto_started]
      Rails.logger.info "[UpdateStateJob] Auto-started radio playlist (queue empty)"
    elsif result[:changed]
      Rails.logger.info "[UpdateStateJob] Switched to playlist: #{result[:playlist]}"
    else
      Rails.logger.debug "[UpdateStateJob] Already playing correct playlist: #{result[:playlist]}"
    end

    result = ManagePlayState.call
    if result[:error]
      Rails.logger.error "[UpdateStateJob] Error managing play state: #{result[:error]}"
    end

    # Also check queue sync status
    if request_queue.sync_status == "out_of_sync"
      Rails.logger.warn "[UpdateStateJob] Queue is out of sync, triggering sync job"
      SyncQueuePlaylistJob.perform_later
    end

  rescue => e
    Rails.logger.error "[UpdateStateJob] Error updating radio state: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise to let the job system handle retries
  end
end
