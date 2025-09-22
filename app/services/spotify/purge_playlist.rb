module Spotify
  class PurgePlaylist < ApplicationService
    def initialize(playlist)
      @playlist = playlist
    end

    def call
      tracks = @playlist.tracks
      @playlist.remove_tracks(tracks)
    end
  end
end
