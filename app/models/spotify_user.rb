require "rest-client"
require "base64"

class SpotifyUser < ApplicationRecord
  # In Rails 7+, serialize needs a coder
  serialize :spotify_hash, coder: JSON

  # Find or create user from OAuth hash
  def self.from_omniauth(auth)
    user = find_or_initialize_by(username: auth.info.id)

    user.email = auth.info.email
    user.token = auth.credentials.token
    user.refresh_token = auth.credentials.refresh_token
    user.expires_at = Time.at(auth.credentials.expires_at) if auth.credentials.expires_at
    user.spotify_hash = auth.to_hash

    user.save!
    user
  end

  # Recreate RSpotify::User from stored credentials
  def to_rspotify_user
    # This is the key workaround - recreating the user from the stored auth hash
    if spotify_hash.present?
      RSpotify::User.new(spotify_hash)
    else
      # Fallback: create a minimal auth hash from stored data
      auth_hash = {
        "credentials" => {
          "token" => token,
          "refresh_token" => refresh_token,
          "expires_at" => expires_at&.to_i
        },
        "info" => {
          "id" => username,
          "email" => email
        }
      }
      RSpotify::User.new(auth_hash)
    end
  end

  # Check if token is expired
  def token_expired?
    expires_at.present? && expires_at < Time.current
  end

  # Check if token is about to expire (within 5 minutes)
  def token_expiring_soon?
    expires_at.present? && expires_at < 5.minutes.from_now
  end

  # Refresh the access token using the refresh token
  def refresh_access_token!
    return false unless refresh_token.present?

    begin
      # Use RestClient directly to refresh the token
      # This is what RSpotify does internally
      response = RestClient.post("https://accounts.spotify.com/api/token",
        {
          grant_type: "refresh_token",
          refresh_token: refresh_token
        },
        {
          "Authorization" => "Basic #{Base64.strict_encode64("#{Rails.application.credentials.spotify[:client_id]}:#{Rails.application.credentials.spotify[:client_secret]}")}"
        }
      )

      data = JSON.parse(response.body)

      if data["access_token"]
        self.token = data["access_token"]
        self.expires_at = Time.current + data["expires_in"].seconds

        # Update spotify_hash if present
        if spotify_hash.present?
          spotify_hash["credentials"] ||= {}
          spotify_hash["credentials"]["token"] = data["access_token"]
          spotify_hash["credentials"]["expires_at"] = expires_at.to_i
          spotify_hash["credentials"]["expires"] = true
        end

        save!
        Rails.logger.info "Successfully refreshed token for #{username}"
        true
      else
        Rails.logger.error "Failed to refresh token for #{username}: No access token in response"
        false
      end
    rescue RestClient::Exception => e
      Rails.logger.error "Error refreshing token for #{username}: #{e.message}"
      Rails.logger.error "Response: #{e.response}" if e.respond_to?(:response)
      false
    rescue => e
      Rails.logger.error "Error refreshing token for #{username}: #{e.message}"
      false
    end
  end

  # Get RSpotify user with automatic token refresh
  def to_rspotify_user_with_refresh
    refresh_access_token! if token_expiring_soon?
    to_rspotify_user
  end
end
