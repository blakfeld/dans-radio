class TrackPlayheadJob < ApplicationJob
  queue_as :high_priority

  # This job runs every 30 seconds to track what's currently playing
  # and update the playhead position in the queue

  def perform
    Rails.logger.debug "[TrackPlayheadJob] Checking playhead position"

    # Get the request queue singleton
    request_queue = RequestQueue.get

    # Update the playhead
    result = UpdatePlayhead.call(request_queue: request_queue)

    if result[:updated]
      Rails.logger.info "[TrackPlayheadJob] Playhead moved to: #{result[:current_track]} (position #{result[:current_position]})"

      # If we've moved to a new track, we might need to sync the playlist
      if result[:tracks_removed] && result[:tracks_removed] > 0
        Rails.logger.info "[TrackPlayheadJob] Removed #{result[:tracks_removed]} played tracks"
      end
    elsif result[:reason] == "nothing_playing"
      # This is normal - music might be paused
      Rails.logger.debug "[TrackPlayheadJob] Nothing playing"
    elsif result[:error]
      Rails.logger.error "[TrackPlayheadJob] Error updating playhead: #{result[:error]}"
    end

  rescue => e
    Rails.logger.error "[TrackPlayheadJob] Error: #{e.message}"
    # Don't re-raise - this job runs frequently, we'll try again in 30 seconds
  end
end
