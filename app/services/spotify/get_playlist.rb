module Spotify
  class GetPlaylist < SpotifyService
    def initialize(id: nil, name: nil)
      @id = id
      @name = name
    end

    def call
      if @id.present?
        by_id
      else
        by_name
      end
    end

    private

    def by_id
      RSpotify::Playlist.find(user_name, @id)
    end

    def by_name
      user.playlists.find { |playlist| playlist.name == @name }
    end
  end
end
