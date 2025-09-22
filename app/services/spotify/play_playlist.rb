module Spotify
  class PlayPlaylist < SpotifyService
    def initialize(playlist:, **_options)
      @playlist = playlist
    end

    def call
      # Play the specified playlist
      user.player.play_context(nil, @playlist.uri)
      Rails.logger.info "[PlayPlaylist] Started playing: #{@playlist.name}"
      { success: true, playlist: @playlist.name }
    rescue => e
      Rails.logger.error "[PlayPlaylist] Error playing playlist #{@playlist.name}: #{e.message}"
      { success: false, error: e.message }
    end
  end
end
