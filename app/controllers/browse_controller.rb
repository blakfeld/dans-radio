class BrowseController < ApplicationController
  before_action :check_request_cooldown

  def index
    @search_query = params[:q]&.strip

    # Base query with albums preloaded
    @artists = Artist.includes(:albums)

    # Apply search if query present
    if @search_query.present?
      @artists = @artists.where("LOWER(artists.name) LIKE LOWER(?)", "%#{@search_query}%")
    end

    @artists = @artists.order(:name)

    # Preload some album images for display
    @artists.each do |artist|
      artist.albums.each do |album|
        # Ensure images are loaded
        album.images ||= []
      end
    end

    # Support Turbo Frame requests for seamless updates
    if turbo_frame_request?
      render partial: "artist_results", locals: { artists: @artists, search_query: @search_query }
    end
  end

  private

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
    5.minutes # 5 minute cooldown between requests
  end
end
