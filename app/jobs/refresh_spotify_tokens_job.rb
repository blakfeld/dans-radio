class RefreshSpotifyTokensJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting Spotify token refresh job"

    # Find all users with tokens that are expired or expiring soon
    users_needing_refresh = SpotifyUser.all.select do |user|
      user.refresh_token.present? && (user.token_expired? || user.token_expiring_soon?)
    end

    Rails.logger.info "Found #{users_needing_refresh.count} users needing token refresh"

    users_needing_refresh.each do |user|
      begin
        if user.refresh_access_token!
          Rails.logger.info "Successfully refreshed token for user: #{user.username}"
        else
          Rails.logger.error "Failed to refresh token for user: #{user.username}"
        end
      rescue => e
        Rails.logger.error "Error refreshing token for user #{user.username}: #{e.message}"
      end
    end

    Rails.logger.info "Completed Spotify token refresh job"
  end
end
