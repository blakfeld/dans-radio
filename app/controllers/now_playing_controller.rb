class NowPlayingController < ApplicationController
  before_action :check_request_cooldown

  def index
    @currently_playing = get_currently_playing_track
    # Only count pending and queued requests (exclude currently playing)
    @queue_count = SongRequest.where(status: [ "pending", "queued" ]).count

    # Calculate estimated queue time (excluding currently playing)
    @queue_duration_ms = SongRequest.where(status: [ "pending", "queued" ]).joins(:track).sum("tracks.duration_ms")
    @queue_duration_mins = (@queue_duration_ms / 60000.0).round if @queue_duration_ms > 0

    # Artist browse functionality
    @search_query = params[:q]&.strip
    @artists = Artist.includes(:albums)

    if @search_query.present?
      # Search for specific artists
      @artists = @artists.where("LOWER(artists.name) LIKE LOWER(?)", "%#{@search_query}%")
      @artists = @artists.order(:name).limit(30)
      @discovery_mode = false
    else
      # Show artists for discovery - mix of popular and random
      @discovery_mode = true

      # Get most popular artists
      popular_artists = @artists
        .where.not(popularity: nil)
        .where("popularity > ?", 30)
        .order("popularity DESC")
        .limit(10)

      # Get some random artists for discovery
      random_artists = @artists
        .where.not(albums: { id: nil })
        .joins(:albums)
        .group("artists.id")
        .having("COUNT(albums.id) > 0")
        .order("RANDOM()")
        .limit(10)

      # Combine and remove duplicates
      @artists = (popular_artists + random_artists).uniq.first(20)

      # Get total artist count for display
      @total_artists = Artist.joins(:albums).distinct.count
    end

    # Support Turbo Frame requests for seamless updates
    if turbo_frame_request?
      render partial: "now_playing/artist_results", locals: {
        artists: @artists,
        search_query: @search_query,
        total_artists: @total_artists,
        discovery_mode: @discovery_mode
      }
      return
    end

    respond_to do |format|
      format.html
      format.json { render json: {
        currently_playing: track_json(@currently_playing),
        queue_count: @queue_count,
        queue_duration_mins: @queue_duration_mins
      }}
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

  def get_currently_playing_track
    # Try to get from Spotify first
    service = Spotify::GetCurrentlyPlaying.new
    track_info = service.call

    if track_info && track_info[:track]
      # Try to find or create the track in our database
      spotify_track = track_info[:track]
      track = Track.find_by_spotify_id(spotify_track.id) if spotify_track.respond_to?(:id)

      {
        track: track,
        spotify_track: spotify_track,
        progress_ms: track_info[:progress_ms],
        is_playing: track_info[:is_playing]
      }
    else
      # Check if we have a playing request
      playing_request = SongRequest.playing.first
      if playing_request
        {
          track: playing_request.track,
          spotify_track: nil,
          progress_ms: 0,
          is_playing: false
        }
      else
        nil
      end
    end
  rescue => e
    Rails.logger.error "Error getting currently playing: #{e.message}"
    nil
  end

  def track_json(playing_info)
    return nil unless playing_info

    track = playing_info[:track] || playing_info[:spotify_track]
    return nil unless track

    {
      title: track.respond_to?(:title) ? track.title : track.name,
      artist: if track.respond_to?(:artist)
                track.artist&.name
              elsif track.respond_to?(:artists)
                track.artists.first&.name
              end,
      album: if track.respond_to?(:album)
               track.album&.name
             elsif track.respond_to?(:album) && track.album
               track.album.name
             end,
      duration_ms: track.respond_to?(:duration_ms) ? track.duration_ms : 0,
      progress_ms: playing_info[:progress_ms] || 0,
      is_playing: playing_info[:is_playing] || false
    }
  end
end
