module Spotify
  class QueueSong < SpotifyService
    def initialize(track)
      @track = track
    end

    def call
      user.player.queue(@track.uri)
    end
  end
end
