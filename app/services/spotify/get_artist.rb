module Spotify
  class GetArtist < ApplicationService
    def initialize(name:, id:)
      @name = name
      @id = id
    end

    def call
      query = if @id.present?
        @id
      else
        @name
      end

      RSpotify::Artist.find(query)
    end
  end
end
