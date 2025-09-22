module Spotify
  class ManagePlayback < SpotifyService
    def initialize(should_play: nil)
      @should_play = should_play
    end

    def call
      # Get current playback state
      begin
        current_playback = user.player.currently_playing
        currently_playing = current_playback&.try(:is_playing) || false
      rescue => e
        Rails.logger.warn "[ManagePlayback] Could not get playback state: #{e.message}"
        currently_playing = false
      end

      set_to_play = if @should_play.nil?
        !currently_playing
      else
        @should_play
      end

      if set_to_play && !currently_playing
        user.player.play
      elsif !set_to_play && currently_playing
        # user.player.pause
      end
    end
  end
end
