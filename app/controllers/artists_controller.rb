class ArtistsController < ApplicationController
  before_action :set_artist
  before_action :check_request_cooldown

  def show
    @albums = @artist.albums.order(release_date: :desc)

    # Get top 5 tracks for the artist
    @top_tracks = @artist.top_tracks(limit: 5)

    # If no top tracks cached, try to fetch them
    if @top_tracks.empty? && @artist.spotify_id.present?
      @top_tracks = @artist.fetch_and_cache_top_tracks(limit: 5)
    end

    # Fetch additional artist info from Spotify if needed
    fetch_artist_details if @artist.bio.blank?
  end

  private

  def set_artist
    @artist = Artist.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to browse_path, alert: "Artist not found"
  end

  def check_request_cooldown
    @can_request = !in_cooldown?
    @cooldown_remaining = cooldown_remaining_seconds if in_cooldown?
  end

  def in_cooldown?
    last_request_time = session[:last_request_time]
    return false unless last_request_time

    time_since_request = Time.current - Time.parse(last_request_time)
    time_since_request < cooldown_period
  end

  def cooldown_remaining_seconds
    return 0 unless session[:last_request_time]

    last_request = Time.parse(session[:last_request_time])
    remaining = cooldown_period - (Time.current - last_request)
    [ remaining.to_i, 0 ].max
  end

  def cooldown_period
    5.minutes
  end

  def fetch_artist_details
    begin
      spotify_artist = @artist.to_rspotify_artist
      if spotify_artist
        # Additional details could be fetched here
        # For now, we'll use what we have
      end
    rescue => e
      Rails.logger.error "Error fetching artist details: #{e.message}"
    end
  end
end
