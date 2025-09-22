class ManageCurrentlyPlaying < ApplicationService
  def initialize(request_queue: nil, auto_start: false)
    @request_queue = request_queue || RequestQueue.get
    @auto_start = auto_start
  end

  def call
    # Determine which playlist should be playing based on queue state
    # If there are active requests (playing, queued, or pending), play the request playlist
    # Otherwise, play the fallback radio playlist
    active_requests = @request_queue.song_requests.where(status: [ "playing", "queued", "pending" ])

    playlist = if active_requests.exists?
      Rails.logger.debug "[ManageCurrentlyPlaying] Active requests found: #{active_requests.count}"
      requests_playlist
    else
      Rails.logger.info "[ManageCurrentlyPlaying] No active requests, switching to radio playlist"
      radio_playlist
    end

    # Check what's currently playing
    currently_playing_data = Spotify::GetCurrentlyPlaying.call

    # Check if we're already playing from the correct playlist
    # We need to check both context_uri and the context object
    if currently_playing_data
      current_context_uri = currently_playing_data[:context_uri] ||
                           currently_playing_data[:context]&.uri ||
                           currently_playing_data[:context]&.href&.split("/")&.last&.then { |id| "spotify:playlist:#{id}" if id }

      if current_context_uri == playlist.uri
        Rails.logger.debug "[ManageCurrentlyPlaying] Already playing correct playlist: #{playlist.name}"
        return { changed: false, playlist: playlist.name }
      end

      # If music is playing but from a different context, we should switch
      Rails.logger.info "[ManageCurrentlyPlaying] Current context: #{current_context_uri}, Target: #{playlist.uri}"
    end

    # Only switch if we're not already on the correct playlist
    # If nothing is playing, check if we should auto-start
    if !currently_playing_data || !currently_playing_data[:is_playing]
      if @auto_start && playlist == radio_playlist
        # Auto-start the radio playlist when queue is empty
        Rails.logger.info "[ManageCurrentlyPlaying] Queue empty, auto-starting radio playlist: #{playlist.name}"
        Spotify::PlayPlaylist.call(playlist: playlist)
        return { changed: true, playlist: playlist.name, auto_started: true }
      else
        Rails.logger.info "[ManageCurrentlyPlaying] Nothing currently playing, would play: #{playlist.name}"
        return { changed: false, playlist: playlist.name, should_play: playlist.uri }
      end
    end

    # Only switch if music is playing and it's the wrong playlist
    Rails.logger.info "[ManageCurrentlyPlaying] Switching to playlist: #{playlist.name}"
    Spotify::PlayPlaylist.call(playlist: playlist)

    { changed: true, playlist: playlist.name }
  rescue => e
    Rails.logger.error "[ManageCurrentlyPlaying] Error: #{e.message}"
    { error: e.message, changed: false }
  end

  private

  def requests_playlist
    return @requests_playlist if @requests_playlist.present?

    playlist_name = Rails.application.config.spotify[:request_playlist_name]
    @requests_playlist = Spotify::GetPlaylist.call(name: playlist_name)

    @requests_playlist
  end

  def radio_playlist
    return @radio_playlist if @radio_playlist.present?

    playlist_name = Rails.application.config.spotify[:radio_playlist_name]
    @radio_playlist = Spotify::GetPlaylist.call(name: playlist_name)

    @radio_playlist
  end
end
