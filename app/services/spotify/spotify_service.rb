module Spotify
  class SpotifyService < ApplicationService
    private

    def user
      @user ||= begin
        username = Rails.application.config.spotify[:user_name]
        spotify_user_record = SpotifyUser.find_by(username: username)

        if spotify_user_record
          spotify_user_record.to_rspotify_user
        else
          Rails.logger.warn "No SpotifyUser found for #{username}. Please authenticate first."
          nil
        end
      end
    end

    def user_name
      Rails.application.config.spotify[:user_name]
    end
  end
end
