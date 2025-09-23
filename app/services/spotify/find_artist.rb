module Spotify
  class FindArtist < SpotifyService
    def initialize(name:)
      @name = name
    end

    def call
      RSpotify::Artist.search(@name)
    end
  end
end
