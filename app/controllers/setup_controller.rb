class SetupController < ApplicationController
  before_action :require_admin

  def index
    @spotify_users = SpotifyUser.all
    @configured_username = Rails.application.config.spotify[:user_name]
    @spotify_configured = spotify_credentials_present?
  end

  def spotify_auth
    # Store where to return after OAuth
    session[:return_to] = setup_index_path
    # This initiates the Spotify OAuth flow
    redirect_to "/auth/spotify", allow_other_host: true
  end

  def test_connection
    if current_spotify_user
      begin
        user = current_spotify_user.to_rspotify_user
        playlists = user.playlists(limit: 5)

        flash[:success] = "Successfully connected to Spotify! Found #{playlists.count} playlists."
        redirect_to setup_index_path
      rescue => e
        flash[:alert] = "Error testing connection: #{e.message}"
        redirect_to setup_index_path
      end
    else
      flash[:alert] = "No authenticated Spotify user found"
      redirect_to setup_index_path
    end
  end

  def clear_auth
    SpotifyUser.destroy_all
    flash[:notice] = "All Spotify authentication data has been cleared"
    redirect_to setup_index_path
  end

  def refresh_tokens
    refreshed_count = 0
    failed_count = 0

    SpotifyUser.all.each do |user|
      if user.refresh_token.present? && (user.token_expired? || user.token_expiring_soon?)
        if user.refresh_access_token!
          refreshed_count += 1
        else
          failed_count += 1
        end
      end
    end

    if refreshed_count > 0
      flash[:success] = "Successfully refreshed #{refreshed_count} token(s)"
    elsif failed_count > 0
      flash[:alert] = "Failed to refresh #{failed_count} token(s)"
    else
      flash[:notice] = "No tokens needed refreshing"
    end

    redirect_to setup_index_path
  end

  private

  def spotify_credentials_present?
    credentials = Rails.application.credentials.spotify
    credentials && credentials[:client_id].present? && credentials[:client_secret].present?
  rescue
    false
  end

  def current_spotify_user
    SpotifyUser.find_by(username: Rails.application.config.spotify[:user_name])
  end
end
