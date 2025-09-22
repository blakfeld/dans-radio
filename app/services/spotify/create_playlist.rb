module Spotify
  class CreatePlaylist < ApplicationService
    def initialize(name:, description: nil)
      @name = name
    end

    def call
      user.create_playlist(name: @name, public: false)
    end
  end
end
