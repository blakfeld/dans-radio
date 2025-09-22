module Spotify
  class GetCurrentlyPlaying < SpotifyService
    def call
      # Get the currently playing track (returns the track object directly)
      track = user.player.currently_playing

      # Check if anything is playing
      is_playing = user.player.playing?

      # If nothing is playing and no track, return nil
      return nil unless track || is_playing

      # We need to make a direct API call to get the full playback context
      # RSpotify doesn't provide a method that returns the full context
      begin
        response = RSpotify.get("me/player")

        if response
          context = response["context"]
          # Return the full playback information
          {
            context_uri: context&.dig("uri"),
            track: track,
            is_playing: is_playing,
            progress_ms: response["progress_ms"],
            timestamp: response["timestamp"],
            context: context
          }
        else
          # Fallback if API call fails
          {
            context_uri: nil,
            track: track,
            is_playing: is_playing,
            progress_ms: nil,
            timestamp: nil,
            context: nil
          }
        end
      rescue => api_error
        Rails.logger.warn "Could not get full playback context: #{api_error.message}"
        # Return basic information without context
        {
          context_uri: nil,
          track: track,
          is_playing: is_playing,
          progress_ms: nil,
          timestamp: nil,
          context: nil
        }
      end
    rescue => e
      Rails.logger.error "Failed to get currently playing track: #{e.message}"
      nil
    end
  end
end
