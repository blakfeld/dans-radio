class RequestQueue < ApplicationRecord
  belongs_to :current_track, class_name: "Track", optional: true
  belongs_to :next_track, class_name: "Track", optional: true
  has_many :song_requests, -> { order(:position) }, dependent: :destroy

  validates :playlist_name, presence: true
  validates :sync_status, inclusion: { in: %w[synced out_of_sync recovering] }, allow_nil: true

  # Singleton pattern - there is only ONE queue for the radio station
  def self.get
    @instance ||= first_or_create do |queue|
      queue.playlist_name = Rails.application.config.spotify[:request_playlist_name] || "Dans Radio Queue"
      queue.sync_status = "synced"
      queue.active = true
      queue.ensure_playlist_exists!
    end
  end

  # Reset singleton (useful for testing)
  def self.reset!
    @instance = nil
  end

  def self.count
    get.song_requests.count
  end

  # Ensure the Spotify playlist exists and sync its ID
  def ensure_playlist_exists!
    spotify_playlist = find_or_create_spotify_playlist
    update!(playlist_id: spotify_playlist.id) if spotify_playlist
    spotify_playlist
  end

  # Get the current track that should be playing
  def current_track
    super || song_requests.where(status: "playing").first&.track
  end

  # Get the next track in the queue
  def next_up
    next_request = song_requests.where(status: [ "queued", "pending" ])
                                .order(:position)
                                .first
    next_request&.track || super
  end

  # Peek at upcoming tracks (including current if playing)
  def upcoming_tracks(limit: 10)
    song_requests.where(status: [ "playing", "queued", "pending" ])
                 .order(:position)
                 .limit(limit)
                 .includes(:track)
                 .map(&:track)
  end

  # Add a track to the queue
  def enqueue(track, requester: nil)
    song_request = song_requests.create!(
      track: track,
      track_id: track.spotify_id,
      artist: track.artist&.name,
      track_title: track.title,
      track_uri: track.uri,
      status: "pending",
      position: next_position
    )

    # Add to Spotify playlist if it exists
    if spotify_playlist
      spotify_playlist.add_tracks!([ track.to_rspotify_track ])
      song_request.update!(status: "queued", queued_at: Time.current)
    end

    song_request
  end

  # Remove a track from the queue
  def dequeue(track)
    song_request = song_requests.find_by(track: track, status: [ "pending", "queued" ])
    return unless song_request

    # Remove from Spotify playlist if it exists
    if spotify_playlist && song_request.status == "queued"
      spotify_playlist.remove_tracks!([ track.to_rspotify_track ])
    end

    song_request.destroy
    reorder_positions
  end

  # Mark a track as currently playing
  def mark_as_playing(track)
    ActiveRecord::Base.transaction do
      # Mark any currently playing tracks as played
      song_requests.where(status: "playing").update_all(
        status: "played",
        played_at: Time.current
      )

      # Find and update the track
      song_request = song_requests.find_by(track: track, status: "queued")
      if song_request
        song_request.update!(
          status: "playing",
          played_at: Time.current
        )
        update!(current_track: track)
      end
    end
  end

  # Advance to the next track in queue
  def advance_queue
    ActiveRecord::Base.transaction do
      # Mark current as played
      if current_track
        current_request = song_requests.find_by(track: current_track, status: "playing")
        current_request&.update!(status: "played", played_at: Time.current)
      end

      # Move next to current
      next_request = song_requests.where(status: "queued").order(:position).first
      if next_request
        next_request.update!(status: "playing")
        update!(
          current_track: next_request.track,
          next_track: song_requests.where(status: "queued")
                                   .where.not(id: next_request.id)
                                   .order(:position)
                                   .first&.track
        )
      else
        update!(current_track: nil, next_track: nil)
      end
    end
  end

  # Clear the entire queue
  def clear!
    ActiveRecord::Base.transaction do
      song_requests.destroy_all
      update!(
        current_track: nil,
        next_track: nil,
        position: 0
      )

      # Clear the Spotify playlist
      if spotify_playlist
        tracks = spotify_playlist.tracks
        spotify_playlist.remove_tracks!(tracks) if tracks.any?
      end
    end
  end

  # Sync internal queue with Spotify playlist state
  def sync_with_spotify!(currently_playing: nil, playlist_tracks: [])
    ActiveRecord::Base.transaction do
      update!(last_sync_at: Time.current)

      # If we have a currently playing track, sync it
      if currently_playing
        track = Track.find_by_spotify_id(currently_playing.id)
        if track
          mark_as_playing(track)
        else
          # Track not in our queue - we're out of sync
          mark_out_of_sync!
        end
      end

      # Verify our queue matches the playlist order
      verify_queue_integrity(playlist_tracks)
    end
  end

  # Mark queue as out of sync
  def mark_out_of_sync!
    update!(sync_status: "out_of_sync")
    Rails.logger.warn "RequestQueue #{id} is out of sync with Spotify"
  end

  # Recover from out of sync state by rebuilding from Spotify playlist
  def recover_from_spotify!
    ActiveRecord::Base.transaction do
      update!(sync_status: "recovering")

      playlist = spotify_playlist
      return mark_out_of_sync! unless playlist

      # Clear current queue state
      song_requests.update_all(status: "recovered")

      # Rebuild from playlist tracks
      playlist_tracks = playlist.tracks
      playlist_tracks.each_with_index do |spotify_track, index|
        track = Track.find_by_spotify_id(spotify_track.id)
        next unless track

        song_requests.create!(
          track: track,
          track_id: track.spotify_id,
          artist: track.artist&.name,
          track_title: track.title,
          track_uri: track.uri,
          status: "queued",
          position: index,
          queued_at: Time.current
        )
      end

      update!(sync_status: "synced")
      Rails.logger.info "RequestQueue #{id} recovered from Spotify playlist"
    end
  end

  private

  # Get the configured Spotify user for the radio
  def spotify_user
    @spotify_user ||= begin
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

  def spotify_user_name
    Rails.application.config.spotify[:user_name]
  end

  def spotify_playlist
    return nil unless playlist_id && spotify_user
    @spotify_playlist ||= RSpotify::Playlist.find(spotify_user.id, playlist_id)
  rescue => e
    Rails.logger.error "Failed to load Spotify playlist: #{e.message}"
    nil
  end

  def find_or_create_spotify_playlist
    user = spotify_user
    return nil unless user

    # Find existing playlist
    playlist = user.playlists(limit: 50).find { |p| p.name == playlist_name }

    # Create if doesn't exist
    playlist ||= user.create_playlist!(playlist_name, public: false)

    playlist
  rescue => e
    Rails.logger.error "Failed to find/create Spotify playlist: #{e.message}"
    nil
  end

  def next_position
    (song_requests.maximum(:position) || -1) + 1
  end

  def reorder_positions
    song_requests.where(status: [ "pending", "queued" ])
                 .order(:position)
                 .each_with_index do |request, index|
      request.update_columns(position: index)
    end
  end

  def verify_queue_integrity(playlist_tracks)
    queued_requests = song_requests.where(status: "queued").order(:position)

    # Check if counts match
    if queued_requests.count != playlist_tracks.count
      mark_out_of_sync!
      return false
    end

    # Check if track order matches
    queued_requests.each_with_index do |request, index|
      if request.track.spotify_id != playlist_tracks[index].id
        mark_out_of_sync!
        return false
      end
    end

    update!(sync_status: "synced") if sync_status != "synced"
    true
  end
end
