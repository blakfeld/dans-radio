module Spotify
  class GetPlayed < ApplicationService
    def initialize(limit: 10, after: nil)
      @limit = limit
      @after = after || 2.hours.ago
        .to_i
        .to_s
    end

    def call
      user.player.recently_played(limit: @limit, after: @after)
    end
  end
end
