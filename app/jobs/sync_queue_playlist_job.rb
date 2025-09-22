class SyncQueuePlaylistJob < ApplicationJob
  queue_as :default

  # This job syncs the Spotify queue playlist with the internal RequestQueue state
  # It can be triggered manually or when the queue is detected as out of sync

  def perform(force_rebuild: false)
    Rails.logger.info "[SyncQueuePlaylistJob] Starting queue playlist sync (force_rebuild: #{force_rebuild})"

    # Get the request queue singleton
    request_queue = RequestQueue.get

    # Ensure the playlist exists
    spotify_playlist = request_queue.ensure_playlist_exists!
    unless spotify_playlist
      Rails.logger.error "[SyncQueuePlaylistJob] Could not find or create Spotify playlist"
      return
    end

    # First, clean up any played tracks that might still be in the playlist
    clean_played_tracks(request_queue, spotify_playlist)

    if force_rebuild || request_queue.sync_status == "out_of_sync"
      # Full rebuild: Clear the playlist and rebuild from internal queue state
      rebuild_playlist_from_queue(request_queue, spotify_playlist)
    else
      # Incremental sync: Verify and fix any discrepancies
      sync_playlist_with_queue(request_queue, spotify_playlist)
    end

    Rails.logger.info "[SyncQueuePlaylistJob] Queue playlist sync completed"

  rescue => e
    Rails.logger.error "[SyncQueuePlaylistJob] Error syncing queue playlist: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Mark queue as out of sync if we failed
    request_queue.mark_out_of_sync! rescue nil

    raise # Re-raise to let the job system handle retries
  end

  private

  def clean_played_tracks(request_queue, spotify_playlist)
    Rails.logger.info "[SyncQueuePlaylistJob] Checking for played tracks in playlist"

    # Get all played track IDs from our database
    played_tracks = request_queue.song_requests
                                 .where(status: "played")
                                 .includes(:track)
                                 .filter { |r| r.track.present? }

    return if played_tracks.empty?

    played_spotify_ids = played_tracks.map { |r| r.track.spotify_id }

    # Get current playlist tracks
    playlist_tracks = []
    offset = 0
    limit = 100

    loop do
      batch = spotify_playlist.tracks(offset: offset, limit: limit)
      playlist_tracks.concat(batch)
      break if batch.size < limit
      offset += limit
    end

    # Find any played tracks that are still in the playlist
    tracks_to_remove = playlist_tracks.select { |t| played_spotify_ids.include?(t.id) }

    if tracks_to_remove.any?
      Rails.logger.info "[SyncQueuePlaylistJob] Removing #{tracks_to_remove.count} played tracks from playlist"
      tracks_to_remove.each_slice(100) do |batch|
        spotify_playlist.remove_tracks!(batch)
      end
    else
      Rails.logger.debug "[SyncQueuePlaylistJob] No played tracks found in playlist"
    end
  rescue => e
    Rails.logger.error "[SyncQueuePlaylistJob] Error cleaning played tracks: #{e.message}"
    # Don't fail the whole sync if cleanup fails
  end

  def rebuild_playlist_from_queue(request_queue, spotify_playlist)
    Rails.logger.info "[SyncQueuePlaylistJob] Rebuilding playlist from internal queue state"

    # Clear the playlist
    tracks = spotify_playlist.tracks
    spotify_playlist.remove_tracks!(tracks) if tracks.any?

    # Get all active (non-played) songs in order
    # Include "playing" status to keep the currently playing track
    queued_requests = request_queue.song_requests
                                   .where(status: [ "queued", "pending", "playing" ])
                                   .order(:position)
                                   .includes(:track)

    if queued_requests.any?
      # Get track URIs without making API calls
      track_uris = queued_requests.filter_map do |request|
        if request.track&.uri.present?
          request.track.uri
        elsif request.track&.spotify_id.present?
          "spotify:track:#{request.track.spotify_id}"
        end
      end

      # Add tracks in batches using URIs (Spotify API limits to 100 tracks per request)
      track_uris.each_slice(100) do |batch|
        spotify_playlist.add_tracks!(batch, position: nil)
      end

      # Update all pending requests to queued status
      request_queue.song_requests.where(status: "pending").update_all(
        status: "queued",
        queued_at: Time.current
      )

      Rails.logger.info "[SyncQueuePlaylistJob] Added #{track_uris.count} tracks to playlist"
    end

    # Mark as synced
    request_queue.update!(sync_status: "synced", last_sync_at: Time.current)
  end

  def sync_playlist_with_queue(request_queue, spotify_playlist)
    Rails.logger.info "[SyncQueuePlaylistJob] Performing incremental sync"

    # Get current playlist tracks
    playlist_tracks = []
    offset = 0
    limit = 100

    loop do
      batch = spotify_playlist.tracks(offset: offset, limit: limit)
      playlist_tracks.concat(batch)
      break if batch.size < limit
      offset += limit
    end

    # Get active (non-played) requests
    # Include "playing" status to keep the currently playing track
    queued_requests = request_queue.song_requests
                                   .where(status: [ "queued", "pending", "playing" ])
                                   .order(:position)
                                   .includes(:track)

    # Get any played tracks that might still be in our database
    played_track_ids = request_queue.song_requests
                                    .where(status: "played")
                                    .pluck(:track_id)
                                    .compact
    played_spotify_ids = Track.where(id: played_track_ids).pluck(:spotify_id)

    # Compare and identify discrepancies
    playlist_track_ids = playlist_tracks.map(&:id)
    queue_track_ids = queued_requests.filter { |r| r.track.present? }.map { |r| r.track.spotify_id }

    # Tracks to remove from playlist (in playlist but not in queue OR played tracks still in playlist)
    tracks_to_remove = playlist_track_ids - queue_track_ids

    # Also remove any played tracks that are somehow still in the playlist
    played_tracks_in_playlist = playlist_track_ids & played_spotify_ids
    if played_tracks_in_playlist.any?
      Rails.logger.info "[SyncQueuePlaylistJob] Found #{played_tracks_in_playlist.count} played tracks still in playlist"
      tracks_to_remove = (tracks_to_remove + played_tracks_in_playlist).uniq
    end

    # Tracks to add to playlist (in queue but not in playlist)
    tracks_to_add = queue_track_ids - playlist_track_ids

    # Check order if counts match
    if tracks_to_remove.empty? && tracks_to_add.empty?
      order_correct = true
      queued_requests.each_with_index do |request, index|
        if request.track.nil? || playlist_tracks[index]&.id != request.track.spotify_id
          order_correct = false
          break
        end
      end

      if !order_correct
        Rails.logger.warn "[SyncQueuePlaylistJob] Track order mismatch, rebuilding playlist"
        rebuild_playlist_from_queue(request_queue, spotify_playlist)
        return
      end
    end

    # Remove tracks that shouldn't be in playlist
    if tracks_to_remove.any?
      Rails.logger.info "[SyncQueuePlaylistJob] Removing #{tracks_to_remove.count} tracks from playlist (including #{played_tracks_in_playlist.count} played tracks)"
      tracks_to_remove_objects = playlist_tracks.select { |t| tracks_to_remove.include?(t.id) }
      spotify_playlist.remove_tracks!(tracks_to_remove_objects)
    end

    # Add missing tracks to playlist
    if tracks_to_add.any?
      Rails.logger.info "[SyncQueuePlaylistJob] Adding #{tracks_to_add.count} tracks to playlist"

      # Get track URIs for tracks to add
      track_uris_to_add = queued_requests.select { |r| r.track.present? && tracks_to_add.include?(r.track.spotify_id) }
                                         .filter_map do |r|
                                           if r.track.uri.present?
                                             r.track.uri
                                           elsif r.track.spotify_id.present?
                                             "spotify:track:#{r.track.spotify_id}"
                                           end
                                         end

      track_uris_to_add.each_slice(100) do |batch|
        spotify_playlist.add_tracks!(batch, position: nil)
      end

      # Update pending requests to queued
      request_queue.song_requests.where(status: "pending", track_id: tracks_to_add).update_all(
        status: "queued",
        queued_at: Time.current
      )
    end

    # Update sync status
    request_queue.update!(sync_status: "synced", last_sync_at: Time.current)

    Rails.logger.info "[SyncQueuePlaylistJob] Incremental sync completed: #{tracks_to_remove.count} removed, #{tracks_to_add.count} added"
  end
end
