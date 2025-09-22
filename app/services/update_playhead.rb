class UpdatePlayhead < ApplicationService
  def initialize(request_queue: nil)
    @request_queue = request_queue || RequestQueue.get
  end

  def call
    # Get what's currently playing on Spotify
    currently_playing = Spotify::GetCurrentlyPlaying.call

    unless currently_playing && currently_playing[:is_playing]
      Rails.logger.debug "[UpdatePlayhead] Nothing currently playing"
      return { updated: false, reason: "nothing_playing" }
    end

    current_track = currently_playing[:track]
    unless current_track
      Rails.logger.debug "[UpdatePlayhead] No track information available"
      return { updated: false, reason: "no_track" }
    end

    # Find the track in our database
    track = Track.find_by_spotify_id(current_track.id) if current_track.respond_to?(:id)
    unless track
      Rails.logger.debug "[UpdatePlayhead] Track not in our database: #{current_track.try(:name)}"
      return { updated: false, reason: "track_not_found" }
    end

    # Check if this track is in our queue
    song_request = @request_queue.song_requests
                                 .where(track: track)
                                 .where(status: [ "queued", "playing" ])
                                 .first

    unless song_request
      Rails.logger.debug "[UpdatePlayhead] Track not in active queue: #{track.title}"
      return { updated: false, reason: "not_in_queue" }
    end

    # Update the playhead position and clean up played tracks
    tracks_removed = 0

    ActiveRecord::Base.transaction do
      # Mark all tracks before this position as played
      @request_queue.song_requests
                    .where(status: [ "queued", "playing" ])
                    .where("position < ?", song_request.position)
                    .each do |played_request|
        mark_as_played(played_request)
      end

      # Mark current track as playing if it's not already
      if song_request.status != "playing"
        Rails.logger.info "[UpdatePlayhead] Marking track as playing: #{track.title}"
        song_request.update!(
          status: "playing",
          played_at: Time.current
        )
        @request_queue.update!(
          current_track: track,
          position: song_request.position
        )
      end

      # Update next track
      next_request = @request_queue.song_requests
                                   .where(status: "queued")
                                   .where("position > ?", song_request.position)
                                   .order(:position)
                                   .first
      @request_queue.update!(next_track: next_request&.track)
    end

    # Clean up the playlist after the transaction - remove played tracks from Spotify
    tracks_removed = cleanup_spotify_playlist

    # Check if this was the last song in the queue
    remaining_active = @request_queue.song_requests.where(status: [ "playing", "queued", "pending" ]).count
    queue_empty = remaining_active == 0

    # If queue is now empty, trigger playlist switch to radio with auto-start
    if queue_empty
      Rails.logger.info "[UpdatePlayhead] Queue is now empty, triggering switch to radio playlist"
      ManageCurrentlyPlaying.call(request_queue: @request_queue, auto_start: true)
    end

    Rails.logger.info "[UpdatePlayhead] Playhead updated to position #{song_request.position}: #{track.title}"

    {
      updated: true,
      current_position: song_request.position,
      current_track: track.title,
      next_track: @request_queue.next_track&.title,
      tracks_removed: tracks_removed,
      queue_empty: queue_empty
    }
  rescue => e
    Rails.logger.error "[UpdatePlayhead] Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { updated: false, error: e.message }
  end

  private

  def mark_as_played(song_request)
    Rails.logger.info "[UpdatePlayhead] Marking as played: #{song_request.track_title} (position: #{song_request.position})"

    song_request.update!(
      status: "played",
      played_at: Time.current
    )

    # Schedule removal from database after a delay
    # This gives us a history of recently played tracks
    RemovePlayedSongJob.set(wait: 30.minutes).perform_later(song_request.id)
  end

  def cleanup_spotify_playlist
    # Get the Spotify playlist
    playlist = @request_queue.spotify_playlist
    return 0 unless playlist

    # Get all played tracks that are still in the playlist
    played_requests = @request_queue.song_requests
                                    .where(status: "played")
                                    .where.not(track_id: nil)
                                    .includes(:track)

    return 0 if played_requests.empty?

    # Get current playlist tracks
    playlist_tracks = []
    offset = 0
    limit = 100

    loop do
      batch = playlist.tracks(offset: offset, limit: limit)
      playlist_tracks.concat(batch)
      break if batch.size < limit
      offset += limit
    end

    # Find tracks to remove (played tracks that are still in playlist)
    tracks_to_remove = []
    played_requests.each do |request|
      next unless request.track

      # Find this track in the playlist
      playlist_track = playlist_tracks.find { |t| t.id == request.track.spotify_id }
      tracks_to_remove << playlist_track if playlist_track
    end

    # Remove played tracks from Spotify playlist
    if tracks_to_remove.any?
      Rails.logger.info "[UpdatePlayhead] Removing #{tracks_to_remove.count} played tracks from Spotify playlist"
      tracks_to_remove.each_slice(100) do |batch|
        playlist.remove_tracks!(batch)
      end
      return tracks_to_remove.count
    end

    0
  rescue => e
    Rails.logger.error "[UpdatePlayhead] Error cleaning up Spotify playlist: #{e.message}"
    # Don't fail the whole operation if cleanup fails
    0
  end
end
