module Spotify
  class GetQueue < ApplicationService
    def call
      user.player.next_up
    end
  end
end
