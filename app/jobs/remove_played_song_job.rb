class RemovePlayedSongJob < ApplicationJob
  queue_as :low_priority

  def perform(song_request_id)
    song_request = SongRequest.find_by(id: song_request_id)

    # Only remove if it's marked as played
    if song_request && song_request.status == "played"
      Rails.logger.info "[RemovePlayedSongJob] Removing played song: #{song_request.track_title}"
      song_request.destroy
    elsif song_request
      Rails.logger.info "[RemovePlayedSongJob] Song not played yet, keeping: #{song_request.track_title}"
    end
  rescue => e
    Rails.logger.error "[RemovePlayedSongJob] Error removing played song: #{e.message}"
    # Don't retry - if we can't remove it, it's not critical
  end
end
