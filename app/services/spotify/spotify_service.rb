module Spotify
  class SpotifyService < ApplicationService
    def user_name
      Rails.application.config.spotify[:user_name]
    end

    def user
      # This is the workaround for the @@users_credentials issue
      # We recreate the RSpotify::User from persisted credentials
      # instead of relying on RSpotify::User.find which depends on class variables

      @user ||= begin
        spotify_user = SpotifyUser.find_by(username: user_name)

        if spotify_user
          # Use the method that automatically refreshes tokens
          spotify_user.to_rspotify_user_with_refresh
        else
          # Fallback to the original method (will fail if class variable is cleared)
          # You'll need to authenticate via OAuth first to create a SpotifyUser record
          Rails.logger.warn "No SpotifyUser found for #{user_name}. Please authenticate via OAuth first."
          RSpotify::User.find(user_name)
        end
      end
    end
  end
end
