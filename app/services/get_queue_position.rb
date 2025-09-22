class GetQueuePosition < ApplicationService
  def initialize(request_queue: nil)
    @request_queue = request_queue || RequestQueue.get
  end

  def call
    return { error: "No active queue found" } unless @request_queue

    # Get currently playing track from Spotify
    currently_playing_data = Spotify::GetCurrentlyPlaying.call

    # Get the playlist tracks to verify integrity
    playlist_tracks = get_playlist_tracks

    # Process the sync
    sync_result = sync_queue_position(currently_playing_data, playlist_tracks)

    # Return the current queue state
    {
      success: sync_result[:success],
      current_track: @request_queue.current_track,
      next_track: @request_queue.next_up,
      position: @request_queue.position,
      sync_status: @request_queue.sync_status,
      message: sync_result[:message],
      currently_playing_spotify: currently_playing_data
    }
  rescue => e
    Rails.logger.error "Failed to get queue position: #{e.message}"
    { error: e.message, success: false }
  end

  private

  def sync_queue_position(currently_playing_data, playlist_tracks)
    # No track playing on Spotify
    if currently_playing_data.nil? || currently_playing_data[:track].nil?
      return handle_no_track_playing
    end

    spotify_track = currently_playing_data[:track]
    is_playing = currently_playing_data[:is_playing]

    # Find the track in our database
    track = Track.find_by_spotify_id(spotify_track.id)

    # Check if this track is what we expected
    expected_next = @request_queue.next_track
    current = @request_queue.current_track

    if track == expected_next
      # The expected next track is now playing - advance our queue
      handle_expected_track_playing(track)
    elsif track == current
      # Still playing the same track - no change needed
      handle_same_track_playing(track, is_playing)
    elsif track_in_queue?(track)
      # A track from our queue is playing, but not what we expected
      handle_unexpected_track_playing(track, playlist_tracks)
    else
      # Track playing is not in our queue at all
      handle_unknown_track_playing(spotify_track, playlist_tracks)
    end
  end

  def handle_no_track_playing
    Rails.logger.info "No track currently playing on Spotify"
    { success: true, message: "No track playing" }
  end

  def handle_expected_track_playing(track)
    Rails.logger.info "Expected track #{track.title} is now playing - advancing queue"

    @request_queue.advance_queue
    @request_queue.update!(sync_status: "synced", last_sync_at: Time.current)

    # Check if we need to remove from Spotify playlist (if using queue instead of playlist)
    # This depends on your implementation strategy

    { success: true, message: "Queue advanced to expected track" }
  end

  def handle_same_track_playing(track, is_playing)
    Rails.logger.debug "Same track #{track.title} still playing"

    # Update playing status if needed
    if is_playing
      song_request = @request_queue.song_requests.find_by(track: track)
      song_request&.update!(status: "playing") if song_request&.status != "playing"
    end

    @request_queue.update!(last_sync_at: Time.current) if @request_queue.sync_status == "synced"

    { success: true, message: "Same track still playing" }
  end

  def handle_unexpected_track_playing(track, playlist_tracks)
    Rails.logger.warn "Unexpected track #{track.title} is playing - queue may be out of sync"

    # Try to recover by finding where we are in the queue
    song_request = @request_queue.song_requests.find_by(track: track, status: [ "queued", "pending" ])

    if song_request
      # Jump to this position in our queue
      Rails.logger.info "Jumping to position #{song_request.position} in queue"

      # Mark all previous tracks as played
      @request_queue.song_requests
                    .where("position < ?", song_request.position)
                    .where(status: [ "pending", "queued" ])
                    .update_all(status: "played", played_at: Time.current)

      # Mark this track as playing
      @request_queue.mark_as_playing(track)
      @request_queue.update!(sync_status: "synced", last_sync_at: Time.current)

      { success: true, message: "Queue position adjusted to match Spotify" }
    else
      # Can't find track in queue - need to recover
      handle_corrupted_queue(playlist_tracks)
    end
  end

  def handle_unknown_track_playing(spotify_track, playlist_tracks)
    Rails.logger.warn "Unknown track #{spotify_track.name} playing - not in our queue"

    # Check if the playlist context matches our playlist
    context = currently_playing_data[:context]
    if context && context.type == "playlist" && context.href&.include?(@request_queue.playlist_id)
      # Playing from our playlist but track not in database
      # Try to recover from playlist state
      handle_corrupted_queue(playlist_tracks)
    else
      # Playing from a different context - just note it
      Rails.logger.info "Track playing from different context: #{context&.type}"
      { success: true, message: "Playing from different source" }
    end
  end

  def handle_corrupted_queue(playlist_tracks)
    Rails.logger.error "Queue is corrupted - attempting recovery"

    @request_queue.mark_out_of_sync!

    # Attempt to recover from Spotify playlist
    if @request_queue.recover_from_spotify!
      { success: true, message: "Queue recovered from Spotify playlist" }
    else
      { success: false, message: "Failed to recover queue - manual intervention may be needed" }
    end
  end

  def track_in_queue?(track)
    @request_queue.song_requests.where(track: track).exists?
  end

  def get_playlist_tracks
    return [] unless @request_queue.playlist_id

    username = Rails.application.config.spotify[:user_name]
    playlist = RSpotify::Playlist.find(username, @request_queue.playlist_id)
    playlist.tracks(limit: 100)
  rescue => e
    Rails.logger.error "Failed to get playlist tracks: #{e.message}"
    []
  end

  def currently_playing_data
    @currently_playing_data ||= Spotify::GetCurrentlyPlaying.call
  end
end
