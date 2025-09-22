class AlbumsController < ApplicationController
  before_action :check_request_cooldown
  before_action :set_album

  def show
    @artist = @album.artist
    @tracks = @album.tracks.order(:track_number)

    # If no tracks are present, try to fetch them from Spotify
    if @tracks.empty? && @album.spotify_id.present?
      fetch_album_tracks
      @tracks = @album.tracks.order(:track_number)
    end
  end

  private

  def set_album
    @album = Album.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Album not found"
    redirect_to browse_path
  end

  def fetch_album_tracks
    begin
      spotify_album = @album.to_rspotify_album
      return unless spotify_album

      # Fetch all tracks for the album
      all_tracks = []
      offset = 0
      limit = 50

      loop do
        tracks_batch = spotify_album.tracks(limit: limit, offset: offset)
        all_tracks.concat(tracks_batch)

        break if tracks_batch.size < limit
        offset += limit
      end

      # Create track records
      all_tracks.each do |spotify_track|
        # Check if track already exists for THIS album specifically
        track = Track.find_by(spotify_id: spotify_track.id, album_id: @album.id)

        if track.nil?
          # Track doesn't exist for this album, check if it exists elsewhere
          existing_track = Track.find_by(spotify_id: spotify_track.id)

          if existing_track && existing_track.album_id != @album.id
            # Track exists but for a different album
            # This could happen with compilations or re-releases
            Rails.logger.info "Track '#{spotify_track.name}' (#{spotify_track.id}) already exists for album #{existing_track.album_id}. Creating separate record for album #{@album.id}"
            track = Track.create!(
              spotify_id: spotify_track.id,
              title: spotify_track.name,
              album_id: @album.id,
              duration_ms: spotify_track.duration_ms,
              explicit: spotify_track.explicit,
              href: spotify_track.href,
              is_playable: spotify_track.is_playable,
              preview_url: spotify_track.preview_url,
              track_number: spotify_track.track_number,
              uri: spotify_track.uri,
              popularity: spotify_track.popularity
            )
          else
            # Track doesn't exist at all or we want to update it
            track = Track.find_or_create_by(spotify_id: spotify_track.id) do |t|
              t.title = spotify_track.name
              t.album_id = @album.id
              t.duration_ms = spotify_track.duration_ms
              t.explicit = spotify_track.explicit
              t.href = spotify_track.href
              t.is_playable = spotify_track.is_playable
              t.preview_url = spotify_track.preview_url
              t.track_number = spotify_track.track_number
              t.uri = spotify_track.uri
              t.popularity = spotify_track.popularity
            end

            # Ensure track is associated with the correct album
            if track.album_id != @album.id
              track.update!(album_id: @album.id)
            end
          end
        end
      end
    rescue => e
      Rails.logger.error "Error fetching tracks for album #{@album.name}: #{e.message}"
    end
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
end
